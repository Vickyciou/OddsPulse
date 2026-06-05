# Live Odds Module

本文件記錄 OddsPulse live odds data pipeline 的現況，包含初始資料載入、mock WebSocket、thread-safe store、subscriber lifecycle 與 reconnect。

## Module Scope

| 類別 | 主要型別 | 職責 |
|:---|:---|:---|
| Provider | `LiveOddsProvider`、`LiveOddsProviderProtocol` | odds 資料單一入口，管理 cache-first flow、background refresh trigger、live feed、store updates、subscriber count 與 reconnect |
| Repository | `RecordsRepository`、`RecordsRepositoryProtocol` | 平行呼叫 REST mock services、執行 mapper，回傳 `[MatchRecord]` |
| REST mock | `MockMatchesService`、`MockOddsService` | 從 bundled JSON fixtures 讀取 matches 與 initial odds |
| WebSocket service | `MockOddsWebSocketService`、`OddsWebSocketServiceProtocol` | Provider-facing connect/disconnect boundary，包裝 WebSocket client |
| WebSocket mock | `MockOddsWebSocketClient`、`OddsWebSocketEvent` | 使用 `Timer` 模擬 live odds batch updates |
| Store | `OddsStore`、`Snapshot` | `OddsStore` 提供 actor-isolated canonical state；`Snapshot` 管理 records、lookup index、ordering 與 mutation |
| Policy | `ReconnectPolicy` | reconnect delay、jitter 與 retry limit |

## Public Interface

`LiveOddsProviderProtocol` 是 ViewModel 使用的資料入口。現況為 main-actor isolated protocol，並要求 conforming provider 可安全跨 concurrency boundary 持有。

```swift
@MainActor
protocol LiveOddsProviderProtocol: Sendable {
    func stream() -> AsyncStream<LiveOddsEvent>
}
```

`LiveOddsEvent` 是 provider 對 ViewModel 的事件契約：

| Event | 語意 |
|:---|:---|
| `.loading` | snapshot 為空，開始刷新 |
| `.recordsLoaded([MatchRecord])` | 刷新結果或 cached snapshot |
| `.oddsUpdated(changedRecords:)` | 已知 match 的 odds 有異動 |
| `.feedStatusChanged(LiveOddsFeedStatus)` | live feed 連線狀態改變 |
| `.refreshFailed(message:)` | matches/odds 刷新失敗 |

## Refresh Flow

```text
subscriber calls stream()
  -> LiveOddsProvider creates AsyncStream continuation
  -> OddsStore.snapshot()
      -> if snapshot exists: emit recordsLoaded(snapshot.records)
      -> if empty: emit loading
      -> RecordsRepository.fetchRecords()
          -> async let matchesService.fetchMatches()
          -> async let oddsService.fetchInitialOdds()
          -> MatchRecordMapper.makeRecords(matches:odds:)
      -> OddsStore.replaceRecords(records)
          -> Snapshot.replaceRecords(records)
      -> emit recordsLoaded(records)
      -> start live updates
```

`MockMatchesService` 與 `MockOddsService` 皆使用 `Task.sleep` 模擬延遲，再透過 `BundleResourceLoader` 讀取 `Resources/MockData/` 下的 JSON fixture。

## Live Update Flow

```text
LiveOddsProvider.startLiveUpdatesIfNeeded(matchIDs:)
  -> MockOddsWebSocketService.connect(matchIDs:)
      -> MockOddsWebSocketClient.connect(matchIDs:)
          -> yields .connected
          -> Timer repeats every second
          -> yields .oddsUpdated([OddsUpdateDTO])
  -> LiveOddsProvider.handleOddsUpdates(_:)
      -> OddsStore.applyOddsUpdates(_:)
          -> Snapshot.applyOddsUpdates(_:)
      -> emit oddsUpdated(changedRecords:) when known records changed
```

`MockOddsWebSocketService` 目前只保留 provider-facing boundary，`connect(matchIDs:)` 與 `disconnect()` 委派給 `MockOddsWebSocketClient`，不重設 channel lifecycle。

`MockOddsWebSocketClient` 目前：

| 行為 | 現況 |
|:---|:---|
| Scheduler | `Timer` 加到 main run loop 的 `.common` mode |
| Batch size | 每批 1 到 10 筆，受輸入 matchIDs 數量限制 |
| Match IDs | 從 `connect(matchIDs:)` 傳入的 IDs 中抽樣 |
| Empty IDs | yield `.disconnected(reason: .noMatchIDs)` 後 finish stream |
| Disconnect | invalidate timer、清空 connected IDs、finish continuation |

## Cache And Subscriber Lifecycle

`SceneDependencies` 持有 shared `LiveOddsProviderProtocol`，使同一個 scene/session 內建立的新 `MatchesViewModel` 可共用 provider。

```text
SceneDependencies.liveOddsProvider
  -> LiveOddsProvider
      -> OddsStore actor
          -> Snapshot
              -> records snapshot
```

Subscriber lifecycle：

1. 每次 `stream()` 建立一個 subscriber ID 與 continuation。
2. continuation termination 會移除 subscriber。
3. subscriber count 歸零時，provider 取消 refresh task、停止 live updates 並呼叫 WebSocket service `disconnect()`。
4. provider deinit 時會停止 live updates、取消 refresh task 並 finish 所有 continuation。

## Reconnect Behavior

`LiveOddsProvider` 對 unexpected stream end 套用 `ReconnectPolicy`。

| 狀態 | 行為 |
|:---|:---|
| `.connected` | reconnect attempt reset 為 0，emit `.live` |
| `.disconnected(.manual)` | 停止 live update loop |
| `.disconnected(.noMatchIDs)` | emit unavailable message，停止 loop |
| `.disconnected(.streamEnded)` | 依 `ReconnectPolicy` 決定是否重連 |
| `.failed` | emit unavailable message，停止 loop |

`ReconnectPolicy.default` 目前設定 initial delay 1 秒、max delay 8 秒、jitter 250ms、max attempts 5。

## Tests

| Test file | 覆蓋範圍 |
|:---|:---|
| `LiveOddsProviderTests.swift` | initial load、cached snapshot、unknown update、stream cancellation、reconnect max attempts |
| `RecordsRepositoryTests.swift` | parallel fetch、API failure propagation、mapper invocation、output records |
| `MockOddsWebSocketServiceTests.swift` | connect/disconnect delegation、event forwarding |
| `MockOddsWebSocketClientTests.swift` | batch IDs、empty IDs、connected event、disconnect finishes stream |
| `SnapshotTests.swift` | upsert、remove、ordering、lookup、replace、apply |
| `OddsStoreTests.swift` | known/unknown odds updates、replace all、snapshot |
| `ReconnectPolicyTests.swift` | exponential delay cap、retry limit |

# Architecture

本文件記錄 OddsPulse 的架構現況、資料流與 thread-safe 設計原則。

模組細節請搭配 [`modules/live-odds.md`](modules/live-odds.md) 與 [`modules/matches-ui.md`](modules/matches-ui.md) 閱讀。

## Current Baseline

OddsPulse 使用 UIKit programmatic UI 與 MVVM。REST mock、WebSocket mock、thread-safe cache 與 reconnect 策略集中在 `LiveOddsProvider`，ViewModel 只消費 provider event 並轉成畫面狀態。

## Current Data Flow

```text
Mock REST services
  -> LiveOddsProvider
      -> MatchRecordMapper
      -> OddsStore actor
          -> LiveOddsEvent.recordsLoaded
              -> MatchesViewModel
                  -> MatchesViewController
                      -> UITableView cells

Mock WebSocket stream
  -> MockOddsWebSocketClient (Timer)
      -> LiveOddsProvider
          -> OddsStore actor
              -> LiveOddsEvent.oddsUpdated
                  -> MatchesViewModel
                      -> row-level update intent
                          -> MatchesViewController

ReconnectPolicy
  -> LiveOddsProvider
      -> LiveOddsEvent.feedStatusChanged
          -> MatchesViewModel
              -> MatchesViewController status label
```

## LiveOddsProvider Interface

`LiveOddsProvider` 是 odds 資料的單一入口。ViewModel 不直接打 API、不直接 connect WebSocket，也不直接讀寫 `OddsStore`。

```swift
@MainActor
protocol LiveOddsProviderProtocol: Sendable {
    func stream() -> AsyncStream<LiveOddsEvent>
}

enum LiveOddsEvent: Equatable {
    case loading
    case recordsLoaded([MatchRecord])
    case oddsUpdated(changedRecords: [MatchRecord])
    case feedStatusChanged(LiveOddsFeedStatus)
    case refreshFailed(message: String)
}

enum LiveOddsFeedStatus: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case unavailable(message: String)
}
```

## Data Merge And Update Flow

1. ViewModel 訂閱 `LiveOddsProvider.stream()`。
2. Provider 先讀 `OddsStore.snapshot()`；若 snapshot 不空，立即 emit `.recordsLoaded(snapshot.records)` 讓 UI 先呈現 cached data。
3. Provider 不論 snapshot 是否存在，都會平行請求 mock `/matches` 與 mock `/odds`；只有 snapshot 為空時才先 emit `.loading`。
4. `MatchRecordMapper` 使用 `matchID` 將比賽基本資料與初始賠率合併，依 `startTime` 升序排序；時間相同時用 `matchID` 作 deterministic tie-breaker。
5. Provider 將 records 寫入 `OddsStore`，再 emit `.recordsLoaded(records)`。
6. Provider 啟動 `MockOddsWebSocketClient`，並 emit feed status。
7. WebSocket 每秒產生 1-10 筆 odds update batch；同一 batch 內避免重複 `matchID`。
8. Provider 將 odds updates 套用到 `OddsStore`，只把 changed records 透過 `.oddsUpdated(changedRecords:)` emit 給 ViewModel。
9. ViewModel 將 changed records 轉成 row view models，產生 row-level update intent，ViewController 只更新受影響的 row。

## Cache Scope

本專案的快取是 in-memory scene/session cache：

- `LiveOddsProvider` 內部持有 `OddsStore actor`。
- `SceneDependencies` 持有 shared `LiveOddsProviderProtocol`，讓同一個 scene 內新建立的 ViewModel 訂閱同一份 provider。
- 切換畫面後，新 ViewModel 可立即從 provider 收到 store snapshot，不需等待 `/matches` 與 `/odds` 重新完成。
- WebSocket 更新會寫回同一個 store，因此快速恢復顯示時會包含最新 WebSocket-applied odds。
- 此快取不做 disk persistence，不承諾 app 被終止後仍可離線恢復；賠率資料仍以 mock API 與 WebSocket feed 為 source of truth。

## Mock WebSocket Client

- `Timer` 只存在於 mock WebSocket client，不放在 ViewController 或 ViewModel。
- `Timer` 加到 main run loop 的 `.common` mode，timer callback 只產生 batch 並透過 `AsyncStream<OddsWebSocketEvent>` 丟出事件，不做 domain mutation 或 UI 更新。
- `LiveOddsProvider` 依賴 `OddsWebSocketClientProtocol`，不依賴具體 mock 實作。
- `connect(matchIDs:)` 開始每秒 batch 推播。
- `connect(matchIDs:)` 會先停止既有 timer，維持同一個 client instance 同時間只有一個 active timer。
- `disconnect()` 停止推播並 `invalidate()` timer；此操作需可重複呼叫且保持安全。
- `Timer` closure 使用 weak capture，避免 retain cycle；`deinit` 需確保 timer 已被 invalidate。
- 若未來改接真實 WebSocket，只替換 client 實作，不影響 ViewModel 與 UI 層。

## Layer Responsibilities

| Layer | 職責 |
|:---|:---|
| ViewController | 建立 UIKit view、綁定 ViewModel output、維護 table rows 並套用 row updates |
| ViewModel | 訂閱 `LiveOddsProvider`、管理畫面狀態、維護 `displayRows` 與 `matchID -> row index`，將 provider event 轉成 row update |
| LiveOddsProvider | 統一資料來源，管理 snapshot、API refresh、WebSocket lifecycle、subscriber count 與 reconnect |
| Service / WebSocket Client | 模擬 `/matches`、`/odds` 與 WebSocket odds update |
| OddsStoreProtocol / OddsStore actor | 保護共享 match/odds state，確保 thread-safe，提供 snapshot 並套用 partial odds updates。`LiveOddsProvider` 依賴 protocol，便於單元測試注入 fake |
| Models | 定義 API/mock model、domain model 與 UI display model |

## State Ownership

- 比賽與賠率的 canonical state 由 `OddsStore` actor 管理。
- `OddsStore` 由 `LiveOddsProvider` 持有，是 provider 的 implementation detail。
- `SceneDependencies` 只持有 shared provider，避免 ViewModel 或 SceneDelegate 直接接觸 store。
- `MatchesViewModel` 標記為 `@MainActor`，持有畫面需要的 display state，不直接暴露 mutable model。
- ViewController 不直接修改 domain state。
- UI 更新需回到 main actor。

## Table Update Strategy

- 初次載入可使用完整 table reload。
- 即時 odds update 不使用整頁 `reloadData()`。
- odds update 應由 ViewModel 轉成 affected row indexes。
- ViewController 收到 live update 時先更新本地 rows，再用 `reloadRows(at:with:)` 只更新受影響的 row。
- 更新 cell 時需注意 cell reuse，避免舊資料閃爍或錯位。

## Live Update Thread-safety Flow

Live odds updates 由 `MockOddsWebSocketClient` 產生，client 持有 `Timer` 並透過 `AsyncStream<OddsWebSocketEvent>` 送出 `[OddsUpdateDTO]` batch。
`LiveOddsProvider` 收到 batch 後交給 `OddsStore` actor 更新 canonical match/odds state。
`OddsStore` 會序列化資料修改、忽略未知 `matchID`，並回傳已更新的 `MatchRecord`。
由於 `MatchesViewModel` 是 `@MainActor`，它會安全地消費 provider event，把 `MatchRecord` 轉成 `MatchRowViewModel`、更新 `displayRows`，再送出 row update intent。
`MatchesViewController` 只負責把這些 row updates 套用到 table view，因此 live odds 更新不需要整頁 `reloadData()`。

## Reconnect Strategy

- `OddsWebSocketClient` 只負責 transport/mock feed，不決定是否重連。
- `LiveOddsProvider` 根據 subscriber count 決定是否需要維持 live feed。
- subscriber count 歸零時，Provider 取消 live task 並呼叫 `disconnect()`，不再重連。
- unexpected stream end 會根據 `ReconnectPolicy` 進行 exponential backoff、max delay、jitter 與 retry limit。
- `ReconnectPolicy.default.maxAttempts` 為 5；超過後 emit `.feedStatusChanged(.unavailable(message: "Live odds unavailable"))`。
- UI 顯示產品語意，例如 `Live`、`Reconnecting odds...`、`Live odds unavailable`，不顯示 WebSocket 技術細節。

## Concurrency Direction

- 使用 Swift Concurrency 表達 mock REST request、state access 與 provider async workflow。
- mock WebSocket 依題目要求使用 `Timer` 模擬推播節奏。
- `LiveOddsProvider` 與 `MatchesViewModel` 的長生命週期 observation 使用可取消的 task，並在 subscriber 或 ViewModel 結束時停止。
- actor 用於保護共享 mutable state。
- 長生命週期 task、timer 或 stream 需有明確停止機制；ViewModel 釋放時需 cancel observation task，Provider 無 subscriber 時需 disconnect WebSocket client。
- 修改 concurrency 相關程式碼時，使用 `swift-concurrency-pro` 做檢查。

## Build Concurrency Settings

| Target | 設定 | 現況 |
|:---|:---|:---|
| App target | `SWIFT_VERSION` | `5.0` |
| App target | `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` |
| App target | `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` |
| Test targets | `SWIFT_VERSION` | `5.0` |
| Test targets | `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` |

目前 app target 大量 UI 與 provider-facing code 受 main actor isolation 影響；若切換到 Swift 6 或調整 actor isolation，需同步檢查 `LiveOddsProviderProtocol`、`MatchesViewModel`、fake providers 與 `OddsWebSocketClientProtocol` 的呼叫邊界。

## Current Test Coverage

| 測試範圍 | 現有覆蓋 |
|:---|:---|
| Sorting | `MatchRecordMapperTests.swift` 驗證 `startTime` 升序與 deterministic tie-breaker |
| Merge logic | `MatchRecordMapperTests.swift` 驗證 matches + initial odds 合併、缺少 odds、未知 odds 與 invalid start time |
| Odds update | `OddsStoreTests.swift` 驗證 known / unknown odds updates、replace all 與 snapshot |
| WebSocket batch | `MockOddsWebSocketClientTests.swift` 驗證 batch match IDs、empty IDs、connected event 與 disconnect stream finish |
| Provider output | `LiveOddsProviderTests.swift` 驗證 initial load、cached snapshot、unknown update、subscriber cancellation 與 reconnect max attempts |
| ViewModel output | `MatchesViewModelTests.swift` 驗證 loading、loaded、failed、row update、feed status 與 stream cancellation |
| Row formatting | `MatchRowViewModelMapperTests.swift` 驗證 unavailable odds 顯示 |
| Reconnect policy | `ReconnectPolicyTests.swift` 驗證 delay cap 與 retry limit |

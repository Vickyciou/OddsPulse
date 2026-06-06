# Architecture

本文件記錄 OddsPulse 的架構現況、資料流與 thread-safe 設計原則。

模組細節請搭配 [`modules/live-odds.md`](modules/live-odds.md) 與 [`modules/matches-ui.md`](modules/matches-ui.md) 閱讀。

## Current Baseline

OddsPulse 使用 UIKit programmatic UI 與 MVVM。`LiveOddsProvider` 是 odds 資料的單一入口，管理 cache-first flow、background refresh、WebSocket subscription、store updates、subscriber lifecycle 與 event emission。`RecordsRepository` 負責平行請求 mock REST services 並呼叫 mapper。`MockOddsWebSocketService` 管理 WebSocket connect/disconnect boundary、DTO→domain mapping 與 reconnect policy。`OddsStore` actor 持有 `Snapshot`，讓 actor isolation 與 records/index/ordering 資料結構責任分離。

## Data Flow

```text
Mock REST services (matches + odds)
  → RecordsRepository → MatchRecordMapper
        ↓
Mock WebSocket stream (Timer-based)
  → MockOddsWebSocketService → ReconnectPolicy
        ↓
  LiveOddsProvider
    → OddsStore actor → Snapshot
    → LiveOddsEvent stream
        ↓
  MatchesViewModel (@MainActor)
    → onStateChange / onRowIndexesUpdated / onFeedStatusChange
        ↓
  MatchesViewController
    → UITableView（state change 用 reloadData，odds update 用 reloadRows）
```

### 資料合併與更新流程

1. ViewModel 訂閱 `LiveOddsProvider.stream()`。
2. Provider 先讀 `OddsStore.snapshot()`：若 snapshot 不空，立即 emit cached records；若為空，emit `.loading`。
3. Provider 呼叫 `RecordsRepository.fetchRecords()` 平行請求 mock `/matches` 與 `/odds`，透過 `MatchRecordMapper` 依 `matchID` 合併、依 `startTime` 升序排序（時間相同以 `matchID` tie-break）。
4. Provider 將 records 寫入 `OddsStore`，emit `.recordsLoaded`，再以最新 match IDs 啟動 WebSocket live feed。
5. WebSocket 每秒產生 1-10 筆 odds update batch；`MockOddsWebSocketService` 將 socket DTO 轉成 domain `OddsUpdate`。
6. Provider 將 updates 套用到 `OddsStore`，只把 changed records 透過 `.oddsUpdated` emit 給 ViewModel。
7. ViewModel 將 changed records 轉成 row view models，計算 affected row indexes；ViewController 只 reload 受影響的 visible rows。

## LiveOddsProvider Interface

`LiveOddsProvider` 對 ViewModel 暴露單一 `AsyncStream<LiveOddsEvent>`。事件語意：

| Event | 語意 |
|:---|:---|
| `.loading` | snapshot 為空，正在刷新 |
| `.recordsLoaded([MatchRecord])` | 初始載入或 cache hit |
| `.oddsUpdated(changedRecords:)` | 已知 match 的 odds 異動 |
| `.feedStatusChanged(LiveOddsFeedStatus)` | WebSocket 連線狀態改變（idle / connecting / live / reconnecting / unavailable） |
| `.refreshFailed(message:)` | matches/odds 刷新失敗 |

ViewModel 不直接打 API、不 connect WebSocket、不讀寫 `OddsStore`，只透過此 stream 消費事件。

## Layer Responsibilities

| Layer | 職責 |
|:---|:---|
| ViewController | 建立 UIKit view、綁定 ViewModel output、套用 table reload 或 row update |
| ViewModel | 訂閱 `LiveOddsProvider`、管理畫面 state、維護 `displayRows` 與 `matchID → row index` mapping |
| LiveOddsProvider | 統一資料入口：cache-first flow、background refresh、WebSocket subscription、subscriber lifecycle、store updates、event emission |
| RecordsRepository | 平行請求 `/matches` 與 `/odds`、呼叫 mapper，回傳 `[MatchRecord]` |
| MockOddsWebSocketService | Provider-facing connect/disconnect boundary、DTO→domain mapping、reconnect policy |
| MockOddsWebSocketClient | Timer-backed mock feed、batch generation、stream continuation lifecycle |
| OddsStore actor | Actor-isolated canonical state、snapshot replacement、odds update entry point |
| Snapshot | Records storage、lookup index、ordering、CRUD 與 odds update mutation |

## State Ownership

- 比賽與賠率的 canonical state 由 `OddsStore` actor 管理，records/index/ordering 儲存在 `Snapshot`。
- `OddsStore` 由 `LiveOddsProvider` 持有，為 provider 的 implementation detail。
- `SceneDependencies` 只持有 shared `LiveOddsProviderProtocol`，避免 ViewModel 或 SceneDelegate 直接接觸 store。
- `MatchesViewModel` 標記為 `@MainActor`，持有畫面 display state，不直接暴露 mutable model。
- ViewController 不直接修改 domain state。

## Cache Scope

Scene/session in-memory cache，由 shared `LiveOddsProvider` 內部的 `OddsStore` actor 保存：

- 同 scene 內新建立的 ViewModel 可立即從 provider 收到 cached snapshot，不需等待 `/matches` 與 `/odds` 重新完成。
- WebSocket 更新寫回同一個 store，快速切換畫面時賠率保持最新。
- Cached snapshot 只用於 immediate render；refresh 失敗時保留 cached UI 並 emit refresh failure，但不以 cached match IDs 啟動 WebSocket。
- 不做 disk persistence。

## Reconnect Strategy

- `MockOddsWebSocketService` 管理 connect/disconnect；unexpected stream end 時依 `ReconnectPolicy`（exponential backoff、max delay、jitter、max 5 attempts）決定是否重連。
- Subscriber count 歸零時，Provider 取消 live task 並 disconnect，不再重連。
- UI 顯示產品語意（`Live`、`Reconnecting odds...`、`Live odds unavailable`），不顯示 WebSocket 技術細節。

## Table Update Strategy

- 初次載入與整體 state change（loading / loaded / failed）使用 `reloadData()`。
- 即時 odds update 由 ViewModel 計算 affected row indexes，ViewController 使用 `reloadRows(at:with:)` 只更新受影響的 visible rows。
- 更新 cell 時需注意 reuse，避免舊資料閃爍或錯位。

## Concurrency Direction

- 使用 Swift Concurrency（`async/await`、`AsyncStream`、`Task`、actor）表達 mock REST、state access 與 provider workflow。
- mock WebSocket 使用 `Timer` 搭配 `AsyncStream<OddsWebSocketEvent>` 模擬推播節奏。
- `LiveOddsProvider` 與 `MatchesViewModel` 的長生命週期 observation 使用可取消的 `Task`；ViewModel 釋放時 cancel observation task，Provider subscriber 歸零時 disconnect WebSocket。
- actor 用於保護共享 mutable state（`OddsStore`）。
- `Timer` closure 使用 weak capture，`deinit` 確保 timer invalidate。
- 修改 concurrency 相關程式碼時，使用 `swift-concurrency-pro` 做檢查。

# OddsPulse

## 架構概要

OddsPulse 採用 UIKit programmatic UI 與 MVVM。`MatchesViewController` 只負責 UIKit 顯示、binding 與 table view 更新；`MatchesViewModel` 消費 provider event，轉成畫面狀態、row view models 與 row-level update intent。

資料流由 `LiveOddsProvider` 作為 ViewModel 的單一入口。Provider 負責 cache-first flow、refresh orchestration、Store updates、WebSocketService start/stop 與 event emission。`RecordsRepository` 負責 matches / initial odds API orchestration 與 mapper invocation。`MockOddsWebSocketService` 負責 WebSocket connect/disconnect/reconnect、receive loop、connection state 與 socket DTO-to-domain mapping；`MockOddsWebSocketClient` 維持 timer-backed transport/mock feed 角色。

### Swift Concurrency / Combine 使用場景

- 目前非同步流程以 Swift Concurrency 為主，尚未使用 Combine。
- mock REST service 使用 `async throws` 與 `Task.sleep` 模擬延遲，`RecordsRepository` 透過 `async let` 平行取得 matches 與 initial odds。
- provider 與 mock WebSocket service 使用 `AsyncStream` 表達事件串流，例如 `.recordsLoaded`、`.oddsUpdated`、`.feedStatusChanged`。
- `Task` 用於長生命週期 observation、資料刷新、live odds loop 與 WebSocketService reconnect backoff；ViewModel 釋放或停止觀察時會 cancel task。
- `@MainActor` 用於保護 UI 相關狀態與 callback 邊界，確保 ViewModel state 與 ViewController render 都在主執行緒。

### Thread-safe 資料存取

- 比賽與賠率的 canonical state 由 `OddsStore actor` 管理，包含 records array 與 `matchID` index。
- 所有 shared odds state 的讀寫都透過 actor method：`replaceRecords(_:)`、`snapshot()`、`applyOddsUpdates(_:)`，由 actor 序列化存取，避免 concurrent mutation。
- `LiveOddsProvider` 是資料層對 ViewModel 的單一入口；ViewModel 不直接讀寫 `OddsStore`，ViewController 也不直接修改 domain state。
- WebSocketService 先將 socket DTO 轉成 domain `OddsUpdate`；即時賠率更新進入 provider 後，會交給 `OddsStore.applyOddsUpdates(_:)` 套用，只把已知且實際更新的 `MatchRecord` 回傳給 ViewModel。
- `LiveOddsProvider` 與 `MatchesViewModel` 目前皆標記為 `@MainActor`，其訂閱者列表、task reference、畫面 state 與 callbacks 不跨執行緒直接 mutate。
- mock WebSocket 的 `Timer` callback 會切回 `MainActor` 後才送出事件；timer 只負責推播節奏，不直接修改 store 或 UI。

### UI 與 ViewModel 資料綁定

- `MatchesViewController.viewDidLoad()` 會先設定 UIKit view hierarchy，再呼叫 `bindViewModel()`，最後由 `viewModel.start()` 開始訂閱 live odds stream。
- ViewModel 使用 closure output 綁定 UI，而不是 Combine publisher：
  - `onStateChange`：通知 `.idle`、`.loading`、`.loaded(rows)`、`.failed(message)`，ViewController 依狀態切換 loading、message 與 table。
  - `onRowIndexesUpdated`：通知 live odds 影響的 row indexes，ViewController 只針對 visible rows 呼叫 `reloadRows(at:with:)`。
  - `onFeedStatusChange`：通知 live feed 狀態，ViewController 更新連線狀態 label。
- TableView data source 直接讀取 `viewModel.rows`；初次載入或整體狀態變化使用 `reloadData()`，即時賠率更新則使用 row-level reload，避免整頁刷新。
- Cell 只接收 `MatchRowViewModel` 並設定 label text，不持有 domain model，也不處理資料更新邏輯。

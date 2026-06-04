# OddsPulse

## 架構概要

OddsPulse 採用 UIKit programmatic UI 與 MVVM。資料來源由 `LiveOddsProvider` 統一管理，負責初始 mock REST 載入、mock WebSocket 即時賠率推播、快取 snapshot、訂閱者生命週期與重連狀態；`MatchesViewModel` 只消費 provider event，轉成畫面狀態與 row-level update；`MatchesViewController` 只負責 UIKit 顯示與 table view 更新。

### Swift Concurrency / Combine 使用場景

- 目前非同步流程以 Swift Concurrency 為主，尚未使用 Combine。
- mock REST service 使用 `async throws` 與 `Task.sleep` 模擬延遲，`LiveOddsProvider` 透過 `async let` 平行取得 matches 與 initial odds。
- provider 與 mock WebSocket 使用 `AsyncStream` 表達事件串流，例如 `.recordsLoaded`、`.oddsUpdated`、`.feedStatusChanged`。
- `Task` 用於長生命週期 observation、資料刷新、live odds loop 與 reconnect backoff；ViewModel 釋放或停止觀察時會 cancel task。
- `@MainActor` 用於保護 UI 相關狀態與 callback 邊界，確保 ViewModel state 與 ViewController render 都在主執行緒。

### Thread-safe 資料存取

- 比賽與賠率的 canonical state 由 `OddsStore actor` 管理，包含 records array 與 `matchID` index。
- 所有 shared odds state 的讀寫都透過 actor method：`replaceRecords(_:)`、`snapshot()`、`applyOddsUpdates(_:)`，由 actor 序列化存取，避免 concurrent mutation。
- `LiveOddsProvider` 是資料層對 ViewModel 的單一入口；ViewModel 不直接讀寫 `OddsStore`，ViewController 也不直接修改 domain state。
- 即時賠率更新進入 provider 後，會先交給 `OddsStore.applyOddsUpdates(_:)` 套用，只把已知且實際更新的 `MatchRecord` 回傳給 ViewModel。
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

## Future Improvements

- 更理想的架構是讓 `@MainActor` 只留在 ViewController 與 ViewModel，確保 UI 狀態更新都在主執行緒。
- 目前 `LiveOddsProvider` 同時處理初始載入、訂閱者管理、WebSocket lifecycle、reconnect、store 更新與事件輸出，責任偏重。若進一步優化架構，可將它收斂為資料流 facade，只負責協調各 service 並對 ViewModel 輸出 `LiveOddsEvent`。
- 可在 WebSocket client 與 provider 之間新增 `WebSocketService`，專門處理 WebSocket state、reconnect 機制、disconnect 邏輯與 stream lifecycle；`MockOddsWebSocketClient` 則維持較底層的 transport/mock feed 角色。
- matches 與 initial odds API 可由統一的 API service 負責載入，並在 service 層協調 mapper 整合資料，避免 provider 直接理解 API request 與 mapping 細節。
- `OddsService` 可負責 odds record 的業務邏輯，例如套用 odds update、處理 unknown match、決定哪些 records 真的需要通知 UI。
- `OddsStore` actor 應維持單純 CRUD storage，不理解業務流程；它只負責 thread-safe 地保存、讀取與覆蓋資料。
- 拆分後可以大幅降低 `LiveOddsProvider` 的責任，更符合 SRP，也能讓 WebSocket state、API loading、odds 更新邏輯與 provider event 輸出分別測試。
- 這樣可以讓 UI layer 與 data/service layer 的 concurrency boundary 更清楚，也能降低未來改接真實 WebSocket 或真實 API 時的重構成本。
- 目前 `LiveOddsProvider` 會先送出 `OddsStore` snapshot，再用 API 最新資料刷新；後續可在 ViewModel 對 refresh records 做 diff，資料相同時不通知 UI，只有部分異動時走 row-level update，避免整批 reload 造成畫面閃動或 scroll position 被影響。

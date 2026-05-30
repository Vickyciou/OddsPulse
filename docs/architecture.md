# Architecture

本文件記錄 OddsPulse 的架構方向、資料流與 thread-safe 設計原則。

## Current Baseline

目前專案由 Xcode UIKit template 建立，後續需移除 `Main.storyboard` 畫面流程，改用 programmatic UI 建立 root view controller 與 table view。

## Target Architecture

```text
Mock REST services
  -> MatchRepository / OddsRepository
      -> OddsStore actor
          -> MatchesViewModel
              -> MatchesViewController
                  -> UITableView cells

Mock WebSocket stream
  -> MockOddsWebSocketClient (Timer)
      -> MatchesViewModel
          -> OddsStore actor
              -> row-level update intent
                  -> MatchesViewController
```

## Data Merge And Update Flow

1. 平行請求 mock `/matches` 與 mock `/odds`，並從固定 JSON fixture decode DTO。
2. 使用 `matchID` 將比賽基本資料與初始賠率合併。
3. 使用解析後的 `startTime: Date` 依時間升序排序；時間相同時才用 `matchID` 作 deterministic tie-breaker。
4. ViewModel 將合併後的資料轉成 table row view models。
5. `MockOddsWebSocketClient` 使用 `Timer` 每秒產生 1-10 筆 odds update batch。
6. 同一個 batch 內避免重複 `matchID`。
7. 每筆 update 以 `matchID` 找到既有比賽資料並覆蓋最新 odds snapshot。
8. ViewModel 產生 row-level update intent，ViewController 只更新受影響的 row。

## Mock WebSocket Client

- `Timer` 只存在於 mock WebSocket client，不放在 ViewController。
- `Timer` 加到 main run loop 的 `.common` mode，timer callback 只產生 batch 並透過 closure 丟出事件，不做 domain mutation 或 UI 更新。
- ViewModel 依賴 `OddsWebSocketClientProtocol`，不依賴具體 mock 實作。
- WebSocket client 使用 callback closure，例如 `onReceiveOddsUpdates: (([OddsUpdateDTO]) -> Void)?`。
- `connect(matchIDs:)` 開始每秒 batch 推播。
- `connect(matchIDs:)` 會先停止既有 timer，維持同一個 client instance 同時間只有一個 active timer。
- `disconnect()` 停止推播並 `invalidate()` timer；此操作需可重複呼叫且保持安全。
- `Timer` closure 與 ViewModel 設定的 callback 都使用 weak capture，避免 retain cycle；`deinit` 需確保 timer 已被 invalidate。
- 若未來改接真實 WebSocket，只替換 client 實作，不影響 ViewModel 與 UI 層。

## Layer Responsibilities

| Layer | 職責 |
|:---|:---|
| ViewController | 建立 UIKit view、綁定 ViewModel output、維護 table rows 並套用 row updates |
| ViewModel | 載入資料、管理畫面狀態、維護 `displayRows` 與 `matchID -> row index`，將 odds update 轉成 `MatchRowUpdate(index, row)` |
| Repository / Service | 模擬 `/matches`、`/odds` 與 WebSocket odds update |
| Store / Actor | 保護共享 match/odds state，確保 thread-safe |
| Models | 定義 API/mock model 與 UI display model |

## State Ownership

- 比賽與賠率的 canonical state 由 `OddsStore` actor 管理。
- `MatchesViewModel` 標記為 `@MainActor`，持有畫面需要的 display state，不直接暴露 mutable model。
- ViewController 不直接修改 domain state。
- UI 更新需回到 main actor。

## Table Update Strategy

- 初次載入可使用完整 table reload。
- 即時 odds update 不使用整頁 `reloadData()`。
- odds update 應由 ViewModel 轉成 `MatchRowUpdate(index, row)`。
- ViewController 收到 live update 時先更新本地 rows；若 row 目前可見，直接 reconfigure visible cell，若不可見則不做額外 UI work。
- 更新 cell 時需注意 cell reuse，避免舊資料閃爍或錯位。

## Live Update Thread-safety Flow

Live odds updates 由 `MockOddsWebSocketClient` 產生，client 持有 `Timer` 並每秒送出 `[OddsUpdateDTO]` batch。
`MatchesViewModel` 收到 batch 後會橋接到 async work，並交給 `OddsStore` actor 更新 canonical match/odds state。
`OddsStore` 會序列化資料修改、忽略未知 `matchID`，並回傳已更新的 `MatchRecord`。
由於 `MatchesViewModel` 是 `@MainActor`，它會安全地把 `MatchRecord` 轉成 `MatchRowViewModel`、更新 `displayRows`，再送出 `MatchRowUpdate(index, row)`。
`MatchesViewController` 只負責把這些 row updates 套用到 table view，因此 live odds 更新不需要整頁 `reloadData()`。

## Concurrency Direction

- 使用 Swift Concurrency 表達 mock REST request、state access 與 ViewModel async workflow。
- mock WebSocket 依題目要求使用 `Timer` 模擬推播節奏。
- 優先使用 structured concurrency。
- actor 用於保護共享 mutable state。
- 長生命週期 task、timer 或 callback 需有明確停止機制；ViewModel 釋放時需 cancel tasks 並 disconnect WebSocket client。
- 修改 concurrency 相關程式碼時，使用 `swift-concurrency-pro` 做檢查。

## Testing Strategy

| 測試範圍 | 建議 |
|:---|:---|
| Sorting | 測試 `startTime` 升序 |
| Merge logic | 測試 matches + initial odds 合併 |
| Odds update | 測試指定 match 的 odds 更新 |
| Thread safety | 測試 concurrent updates 不造成 state 不一致 |
| WebSocket batch | 測試 batch size、同 batch 不重複 `matchID`、只從輸入 matchIDs 產生 update |
| ViewModel output | 測試 `MatchRowUpdate(index, row)` 指向正確 row 且包含更新後 display data |

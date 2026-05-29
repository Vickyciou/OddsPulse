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

1. 平行請求 mock `/matches` 與 mock `/odds`。
2. 使用 `matchID` 將比賽基本資料與初始賠率合併。
3. 使用解析後的 `startTime` 依時間升序排序。
4. ViewModel 將合併後的資料轉成 table row view models。
5. `MockOddsWebSocketClient` 使用 `Timer` 每秒產生 1-10 筆 odds update batch。
6. 同一個 batch 內避免重複 `matchID`。
7. 每筆 update 以 `matchID` 找到既有比賽資料並覆蓋最新 odds snapshot。
8. ViewModel 產生 row-level update intent，ViewController 只更新受影響的 row。

## Mock WebSocket Client

- `Timer` 只存在於 mock WebSocket client，不放在 ViewController。
- ViewModel 依賴 `OddsWebSocketClientProtocol`，不依賴具體 mock 實作。
- `connect(matchIDs:)` 開始每秒 batch 推播。
- `disconnect()` 停止推播並 `invalidate()` timer。
- `deinit` 需確保 timer 已被 invalidate，避免 retain cycle 或背景持續更新。
- 若未來改接真實 WebSocket，只替換 client 實作，不影響 ViewModel 與 UI 層。

## Layer Responsibilities

| Layer | 職責 |
|:---|:---|
| ViewController | 建立 UIKit view、綁定 ViewModel output、套用 table row updates |
| ViewModel | 載入資料、排序 row view models、將 odds update 轉成 row-level UI update |
| Repository / Service | 模擬 `/matches`、`/odds` 與 WebSocket odds update |
| Store / Actor | 保護共享 match/odds state，確保 thread-safe |
| Models | 定義 API/mock model 與 UI display model |

## State Ownership

- 比賽與賠率的 canonical state 由 store/actor 管理。
- ViewModel 持有畫面需要的 display state，不直接暴露 mutable model。
- ViewController 不直接修改 domain state。
- UI 更新需回到 main actor。

## Table Update Strategy

- 初次載入可使用完整 table reload。
- 即時 odds update 不使用整頁 `reloadData()`。
- odds update 應由 ViewModel 轉成特定 index path 或 row identifier 的更新意圖。
- 更新 cell 時需注意 cell reuse，避免舊資料閃爍或錯位。

## Concurrency Direction

- 使用 Swift Concurrency 表達 mock REST request、state access 與 ViewModel async workflow。
- mock WebSocket 依題目要求使用 `Timer` 模擬推播節奏。
- 優先使用 structured concurrency。
- actor 用於保護共享 mutable state。
- 長生命週期 task、timer 或 callback 需有明確停止機制。
- 修改 concurrency 相關程式碼時，使用 `swift-concurrency-pro` 做檢查。

## Testing Strategy

| 測試範圍 | 建議 |
|:---|:---|
| Sorting | 測試 `startTime` 升序 |
| Merge logic | 測試 matches + initial odds 合併 |
| Odds update | 測試指定 match 的 odds 更新 |
| Thread safety | 測試 concurrent updates 不造成 state 不一致 |
| ViewModel output | 測試 update intent 指向正確 row |

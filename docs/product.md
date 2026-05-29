# Product

本文件記錄 OddsPulse interview homework 的題目需求、scope 與交付項目。

## 題目摘要

OddsPulse 是即時賽事賠率系統。App 需展示約 100 筆比賽資料，整合 mock REST API、mock WebSocket odds update、thread-safe 資料處理與即時 UI 更新。

## Core Requirements

| 類別 | 要求 |
|:---|:---|
| Matches | 模擬 `GET /matches`，回傳約 100 筆比賽資料，包含 `matchID`、`teamA`、`teamB`、`startTime` |
| Initial odds | 模擬 `GET /odds`，回傳每場比賽初始賠率，包含 `matchID`、`teamAOdds`、`teamBOdds` |
| Odds updates | 模擬 WebSocket，每秒最多推播 10 筆指定 match 的新賠率 |
| UI | 使用 `UITableView` 呈現比賽資訊 |
| Sorting | 依比賽時間升序排序，最近的比賽在最上方 |
| Realtime update | odds 更新時只更新對應 cell，不可整頁 reload |
| Performance | 畫面需保持順暢，避免卡頓與頻繁重載 |
| Thread safety | 多執行緒下需確保資料一致性並避免 race condition |

## 假設與邊界

- `GET /matches` 與 `GET /odds` 是彼此獨立的初始資料來源，可平行請求。
- `matchID` 是比賽的穩定唯一識別碼，用於合併 matches、initial odds 與 live odds updates。
- `startTime` 使用 ISO8601 UTC 格式，例如 `2025-07-04T13:00:00Z`。
- mock `/odds` 正常情況會為每場比賽提供初始賠率，但 App 仍需能處理缺少賠率的邊界情境。
- 每筆 WebSocket message 都代表某一場比賽的完整賠率快照，包含 `teamAOdds` 與 `teamBOdds`。
- mock WebSocket 使用 `Timer` 每秒推播一個 batch，每批包含 1-10 筆 odds updates。
- 同一個 batch 內不重複更新同一個 `matchID`。
- mock WebSocket 正常只會針對已知 `matchID` 產生更新。
- 若收到未知 `matchID` 的 update，App 會忽略該 update，並保留診斷資訊。
- 因題目提供的 payload 沒有 sequence number 或 timestamp，out-of-order reconciliation 不列入本次範圍。
- 若實作加分 cache，採用記憶體中的 latest-state cache，不做 disk persistence。

## Technical Constraints

| 項目 | 決策 |
|:---|:---|
| UI framework | UIKit only |
| UI construction | Programmatic UI，不使用 `Main.storyboard` |
| Language | Swift |
| Architecture | MVVM |
| Async | Swift Concurrency 優先 |
| Data source | Mock data，可用 in-memory generator 或 JSON |

## Bonus Scope

| 加分項 | 處理原則 |
|:---|:---|
| WebSocket 自動重連 | 核心需求完成後再做 |
| Cache | 核心需求完成後再做；需清楚說明 cache 邊界 |
| Instruments | 可作為加分驗證，不阻塞核心交付 |

## Non-goals

- 不串接真實後端。
- 不加入登入、搜尋、收藏、下注流程或非題目要求功能。
- 不加入非必要第三方套件。
- 不為了展示架構而建立過度抽象層。

## Delivery Checklist

| 交付項目 | 狀態 |
|:---|:---|
| Source code | 待實作 |
| 架構說明 | 待補，需涵蓋 Swift Concurrency 使用場景、thread-safe 設計、UI/ViewModel binding |
| 操作影片 | 可選 |
| Unit tests | 建議提供 |

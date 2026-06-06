# Product

本文件記錄 OddsPulse 的題目需求、實作範圍、假設邊界與刻意不收的範圍。

## Problem

OddsPulse 是即時賽事賠率系統。App 展示約 100 筆比賽資料，整合 mock REST API、mock WebSocket odds update、thread-safe 資料處理與即時 UI 更新。

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

## Assumptions

- `GET /matches` 與 `GET /odds` 是彼此獨立的初始資料來源，可平行請求。
- `matchID` 使用 `Int`，作為 opaque identifier 用於合併 matches、initial odds 與 live odds updates。
- `startTime` 使用 ISO8601 UTC 格式（例如 `2025-07-04T13:00:00Z`），解析成 `Date` 後依時間升序排序；時間相同以 `matchID` 作 deterministic tie-breaker。
- mock `/odds` 正常情況為每場比賽提供初始賠率，但 App 仍處理缺少賠率的邊界情境：domain 以 `OddsState.available` / `.unavailable` 表達，UI 以 `--` 顯示。
- 每筆 WebSocket message 代表某一場比賽的完整賠率快照，包含 `teamAOdds` 與 `teamBOdds`。
- mock WebSocket 使用 `Timer` 每秒推播一個 batch，每批 1-10 筆 odds updates；同 batch 內不重複同一個 `matchID`。
- mock WebSocket 正常只針對已知 `matchID` 產生更新；收到未知 `matchID` 時 App 忽略該 update 並保留診斷資訊。
- 因 payload 無 sequence number 或 timestamp，out-of-order reconciliation 不列入本次範圍。
- 快取採用 in-memory scene/session cache，不做 disk persistence。

## Technical Constraints

| 項目 | 決策 |
|:---|:---|
| UI framework | UIKit only |
| UI construction | Programmatic UI，不使用 `Main.storyboard` |
| Language | Swift |
| Architecture | MVVM |
| Async | Swift Concurrency 優先 |
| Data source | 固定 JSON fixture |

## Completed Extras

核心需求之外已完成的項目：

| 項目 | 實作方式 |
|:---|:---|
| WebSocket 自動重連 | `ReconnectPolicy`（exponential backoff、max delay、jitter、max 5 attempts） |
| Cache | In-memory scene/session cache，由 `LiveOddsProvider` + `OddsStore` actor 保存 |

## Non-goals

- 不串接真實後端。
- 不加入登入、搜尋、收藏、下注流程或非題目要求功能。
- 不加入非必要第三方套件。
- 不為了展示架構而建立過度抽象層。

## Current Delivery

所有核心需求與兩項加分項已完成。完整架構說明見 [`architecture.md`](architecture.md)，模組細節見 [`modules/live-odds.md`](modules/live-odds.md) 與 [`modules/matches-ui.md`](modules/matches-ui.md)。XCTest 覆蓋 mapping、repository、snapshot、store、WebSocket service/client、provider、ViewModel 與 reconnect policy（10 test files）。

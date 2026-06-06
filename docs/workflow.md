# Workflow

本文件定義 OddsPulse 的開發流程：如何規劃變更、如何驗證、何時更新文件。

## Plan Gate

| 變更規模 | 流程 |
|:---|:---|
| 文件或小型設定 | 簡短說明即可 |
| 影響 navigation、資料流、concurrency 或 table update 策略 | 先提出 plan 並取得確認 |
| 大範圍重構或架構決策變更 | 列出影響範圍、替代方案與驗證方式 |

## Build And Test

```bash
# 每個主要階段完成後至少執行 build
xcodebuild build -project OddsPulse.xcodeproj -scheme OddsPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 有測試後優先執行 full test
xcodebuild test -project OddsPulse.xcodeproj -scheme OddsPulse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

若本機 simulator 名稱不同，先用 `xcrun simctl list devices available` 查詢可用裝置。

## Verification Notes

- 即時 odds update 應能看出 cell 局部更新，不可使用整頁 `reloadData()`。
- mock WebSocket 每秒最多產生 10 筆 update，同 batch 內不重複 `matchID`。
- `disconnect()` 後不應再產生 update。
- ViewModel 釋放時應 cancel 長生命週期 observation task；Provider subscriber 歸零時應 disconnect WebSocket。
- Timer / client 釋放後不應 retain 相關物件。
- 測試聚焦 merge/sort、store update、WebSocket batch invariants 與 ViewModel row update intent；UI 順暢以人工檢查與架構說明補足。
- 若未執行測試或 build，回覆需明確說明原因。

## Architecture Review

變更 concurrency、data flow 或架構邊界時：

- 使用 `swift-concurrency-pro` 檢查 Swift concurrency 正確性。
- 確認 layer responsibilities 沒有被繞過（例如 ViewModel 不直接打 API、ViewController 不直接讀寫 store）。
- 確認新增的 abstraction 有明確的現況需求支撐，而非為了「未來可能」。

## Docs

以下情況需同步更新對應文件：

| 變更 | 需更新的文件 |
|:---|:---|
| 資料流、concurrency、table update 或 state ownership | `architecture.md` |
| API contract、event、模組邊界 | `modules/live-odds.md` 或 `modules/matches-ui.md` |
| 題目 scope、假設、交付項目變更 | `product.md` |
| 新增或移除 source file | `overview.md`（source layout）+ `CLAUDE.md` |

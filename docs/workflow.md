# Workflow

本文件定義 OddsPulse interview homework 的開發流程與驗證節奏。

## Development Order

1. 移除 `Main.storyboard` app flow，建立 programmatic root。
2. 建立 domain DTO/model 與固定 JSON fixture。
3. 實作 mock REST services：matches 與 initial odds，並以平行請求取得初始資料。
4. 補 matches + odds merge 與 `startTime` 排序測試。
5. 建立 ViewModel，完成排序與初始 table render。
6. 實作 `MockOddsWebSocketClient`，內部使用 `Timer` 每秒產生 1-10 筆 odds update batch。
7. 建立 thread-safe store/actor。
8. 串接 row-level odds update，不使用整頁 reload。
9. 補測試與架構說明。
10. 視時間處理加分項：reconnect、cache、Instruments 或 demo video。

## Plan Gate

- 文件與小型設定修改：簡短說明即可。
- 影響 storyboard 移除、navigation、資料流、concurrency 或 table update 策略：需先提出 plan 並取得確認。
- 大範圍重構或改變架構決策：需列出影響範圍、替代方案與驗證方式。

## Build And Test Loop

每個主要階段完成後至少執行：

```bash
xcodebuild build -project OddsPulse.xcodeproj -scheme OddsPulse -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

有測試後優先執行：

```bash
xcodebuild test -project OddsPulse.xcodeproj -scheme OddsPulse -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

若本機 simulator 名稱不同，先用 `xcrun simctl list devices available` 查詢可用裝置。

## Current Verification Coverage

| Test file | 覆蓋範圍 |
|:---|:---|
| `MatchRecordMapperTests.swift` | start time 排序、缺少 odds、未知 odds、invalid start time |
| `RecordsRepositoryTests.swift` | parallel fetch、API failure propagation、mapper invocation、output records |
| `MatchRowViewModelMapperTests.swift` | unavailable odds 顯示 |
| `SnapshotTests.swift` | upsert、remove、ordering、lookup、replace、apply |
| `OddsStoreTests.swift` | known/unknown odds updates、replace all、snapshot |
| `MockOddsWebSocketServiceTests.swift` | connect/disconnect delegation、event forwarding、DTO-to-domain mapping、stream-ended reconnect、manual disconnect no reconnect、reconnect max attempts |
| `MockOddsWebSocketClientTests.swift` | batch match IDs、empty IDs、connected event、disconnect finishes stream |
| `LiveOddsProviderTests.swift` | initial load、cached snapshot、refresh failure、unknown update、subscriber cancellation、WebSocketService start/stop、feed status event mapping |
| `MatchesViewModelTests.swift` | loading、loaded、failed、row update、feed status、stream cancellation |
| `ReconnectPolicyTests.swift` | reconnect delay cap 與 retry limit |

## Verification Notes

- 即時 odds update 應能看出 cell 局部更新。
- 需避免每秒多筆 update 導致 table 卡頓。
- mock WebSocket 每秒最多產生 10 筆 update，且同 batch 內不重複 `matchID`。
- live odds update path 不應呼叫整頁 `reloadData()`。
- `disconnect()` 後不應再產生 update。
- ViewModel 釋放時應 cancel 長生命週期 observation task；Provider 在 subscriber 歸零時應 disconnect WebSocketService。
- ViewModel 或 client 釋放後 timer 不應繼續 retain 相關物件。
- 若用 log 驗證，log 應能區分 initial reload 與 row update 次數。
- 測試聚焦 merge/sort、store update、WebSocket batch invariants 與 ViewModel row update intent；UI 順暢以人工檢查與架構說明補足。
- 若沒有執行測試或 build，回覆需明確說明原因。

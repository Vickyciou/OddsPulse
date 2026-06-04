# OddsPulse

## Future Improvements

- 更理想的架構是讓 `@MainActor` 只留在 ViewController 與 ViewModel，確保 UI 狀態更新都在主執行緒。
- `LiveOddsProvider` 應改為 actor，負責管理訂閱者、初始載入、即時賠率推播與重連狀態。
- `MockOddsWebSocketClient` 應改為 actor，避免資料層依賴 main run loop，讓推播狀態由資料層自行序列化管理。
- `OddsStore` actor 應維持單純 CRUD storage，不理解業務流程；由 `LiveOddsProvider` 作為單一入口操作 store 並負責業務邏輯。
- 這樣可以讓 UI layer 與 data/service layer 的 concurrency boundary 更清楚，也能降低未來改接真實 WebSocket 時的重構成本。
- 目前 `LiveOddsProvider` 會先送出 `OddsStore` snapshot，再用 API 最新資料刷新；後續可在 ViewModel 對 refresh records 做 diff，資料相同時不通知 UI，只有部分異動時走 row-level update，避免整批 reload 造成畫面閃動或 scroll position 被影響。

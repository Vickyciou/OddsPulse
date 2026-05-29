# Interview Quality Rules

本文件定義 OddsPulse 作為 interview homework 的品質標準。

## Scope Control

- 先完成題目核心需求，再處理加分題。
- 不加入題目未要求的產品功能。
- 不加入非必要第三方套件。
- 有任何 scope 擴張，需先說明原因與成本。
- 若題目語意不明，先在文件中記錄採用的假設與邊界，不讓隱含假設散落在程式碼裡。
- 題目明確指定的技術要求需優先遵守；若使用額外抽象，需能說明它如何服務題目需求，而不是替代題目要求。

## Code Quality

- 可讀性優先於炫技。
- 抽象只在能降低實際複雜度時加入。
- 型別與方法命名需讓 reviewer 不依賴註解也能理解。
- 錯誤、loading、empty、updating 狀態需有明確處理。

## Architecture Explanation

交付前需能簡要說明：

- Swift Concurrency 使用在哪些地方。
- 如何確保資料存取 thread-safe。
- UI 與 ViewModel 如何綁定。
- 為什麼 table update 不使用整頁 reload。
- 哪些加分項完成，哪些刻意不做。

## Review Bias

實作時假設 reviewer 會特別看：

- 是否符合 UIKit only。
- 是否遵守 MVVM。
- 是否真的做到 row-level update。
- 是否避免 race condition。
- 是否有測試或清楚的驗證證據。
- 架構是否剛好足夠，而不是過度設計。

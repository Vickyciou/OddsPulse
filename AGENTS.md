# OddsPulse Agent Guide

OddsPulse 是 iOS interview homework：即時賽事賠率系統。實作以題目要求、可審查品質與穩定驗證為優先。

## Project Rules

- 使用 UIKit + Swift，不使用 SwiftUI。
- App UI 使用 programmatic UI，不使用 `Main.storyboard` 建立畫面流程。
- 架構採 MVVM。
- 非同步實作優先使用 Swift Concurrency；只有明確理由才使用 Combine。
- 修改 Swift Concurrency、`Task`、actor、async sequence 或 thread-safety 相關程式碼時，使用 `swift-concurrency-pro` skill 檢查。
- 不加入非必要第三方套件。
- 不擅自擴充題目 scope；加分題需先完成核心需求後再處理。

## Workspace Standards

| 文件 | 用途 |
|:---|:---|
| [`../docs/code_standard.md`](../docs/code_standard.md) | workspace iOS 預設開發規範 |
| [`../docs/workflow.md`](../docs/workflow.md) | Git 操作限制與 Plan Gate |
| [`../docs/workspace.md`](../docs/workspace.md) | workspace 專案清單與入口 |

若本檔與 workspace 預設不一致，以本檔為 OddsPulse 的 project-local 規則。

## Docs Index

| 任務 | 讀哪份文件 |
|:---|:---|
| 了解 homework 題目、scope 與交付項目 | [`docs/product.md`](docs/product.md) |
| 了解架構、資料流與 thread-safe 設計方向 | [`docs/architecture.md`](docs/architecture.md) |
| 了解開發順序與驗證流程 | [`docs/workflow.md`](docs/workflow.md) |
| 檢查 interview homework 品質標準 | [`docs/rules/interview-quality.md`](docs/rules/interview-quality.md) |
| 檢查 UIKit programmatic UI 規則 | [`docs/rules/uikit-programmatic-ui.md`](docs/rules/uikit-programmatic-ui.md) |

## Expected Validation

- 每個實作階段至少執行 build。
- 涉及資料邏輯、排序、thread-safe 或 ViewModel 時，優先補 XCTest。
- 涉及 UI 更新時，需確認 odds update 是局部 row update，不使用整頁 `reloadData()` 作為即時更新機制。


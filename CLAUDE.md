# OddsPulse Agent Guide

OddsPulse 是 iOS interview homework：即時賽事賠率系統，使用 UIKit programmatic UI、MVVM 與 Swift Concurrency 實作 mock REST、mock WebSocket、thread-safe state 與 row-level odds update。

## Project Scope

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

## Tech Stack

| 類別 | 現況 |
|:---|:---|
| Platform | iOS app |
| UI | UIKit、programmatic layout、`UITableView` |
| Architecture | MVVM |
| Async | Swift Concurrency、`AsyncStream`、actor、`Task` |
| Data source | bundled JSON fixtures + mock WebSocket timer |
| Tests | XCTest |

## Docs Index

| 任務 | 讀哪份文件 |
|:---|:---|
| 了解專案現況與文件入口 | [`docs/overview.md`](docs/overview.md) |
| 了解 homework 題目、scope 與交付項目 | [`docs/product.md`](docs/product.md) |
| 了解架構、資料流與 thread-safe 設計方向 | [`docs/architecture.md`](docs/architecture.md) |
| 了解開發順序與驗證流程 | [`docs/workflow.md`](docs/workflow.md) |
| 檢查 interview homework 品質標準 | [`docs/rules/interview-quality.md`](docs/rules/interview-quality.md) |
| 檢查 UIKit programmatic UI 規則 | [`docs/rules/uikit-programmatic-ui.md`](docs/rules/uikit-programmatic-ui.md) |

## Modules

| 模組 | 文件 | 主要程式碼 |
|:---|:---|:---|
| Live odds data pipeline | [`docs/modules/live-odds.md`](docs/modules/live-odds.md) | `Services/RecordsRepository.swift`、`Services/LiveOddsProvider.swift`、`Services/MockOddsWebSocketService.swift`、`Stores/OddsStore.swift`、`Stores/Snapshot.swift` |
| Matches UI | [`docs/modules/matches-ui.md`](docs/modules/matches-ui.md) | `Matches/ViewController/`、`Matches/ViewModel/`、`Matches/View/` |

## Commands

```bash
xcodebuild build -project OddsPulse.xcodeproj -scheme OddsPulse -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -project OddsPulse.xcodeproj -scheme OddsPulse -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

若本機 simulator 名稱不同，先用 `xcrun simctl list devices available` 查詢可用裝置。

## Maintenance Notes

- 文件需忠實反映 codebase 現況，不寫入尚未實作的理想架構。
- 更動資料流、concurrency、table update 或測試策略時，同步更新 `docs/architecture.md`、`docs/workflow.md` 與相關 `docs/modules/` 文件。
- `CLAUDE.md` 與 `AGENTS.md` 必須保持語義等價。

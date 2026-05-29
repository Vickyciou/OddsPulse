# UIKit Programmatic UI Rules

本文件定義 OddsPulse 的 UIKit programmatic UI 規則。

## Required

- 不使用 SwiftUI。
- 不使用 `Main.storyboard` 建立 app 畫面流程。
- 使用 UIKit code 建立 root view controller、table view、cell 與 layout。
- UI 更新必須在 main actor / main thread。

## Storyboard Policy

- `Main.storyboard` 應移除或不再被 app flow 使用。
- `Info.plist` 與 project build settings 不應保留 main storyboard 啟動設定。
- `LaunchScreen.storyboard` 可保留，因為它不是 app runtime UI flow。

## View Construction

- ViewController 拆分 `configureHierarchy()`、`configureConstraints()`、`configureAppearance()` 等 setup 方法。
- Layout 數值使用具名 constants，避免 magic number 散落。
- Table cell 必須正確處理 reuse 狀態。

## Table View Updates

- 初次載入可完整 reload。
- odds 即時更新不可用整頁 `reloadData()` 作為主要機制。
- 需優先使用 row-level update 或直接更新可見 cell。
- 更新策略需避免 cell reuse 錯位。

## Accessibility And Test Hooks

- 重要 UI 元件可加 `accessibilityIdentifier`，方便 UI test 與 debug。
- 這是建議規則，不應優先於核心功能。

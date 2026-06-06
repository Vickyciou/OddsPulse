# Overview

OddsPulse 專案總覽與文件入口。新工程師的第一份閱讀文件。

## Project Snapshot

| 項目 | 現況 |
|:---|:---|
| Project type | iOS app interview homework |
| UI | UIKit programmatic UI |
| Architecture | MVVM |
| Core screen | Matches list with live odds updates |
| Data source | bundled JSON fixtures + mock WebSocket timer |
| State safety | `OddsStore` actor + `Snapshot` |
| Tests | XCTest（10 test files） |

## Current Status

核心需求已全數完成：programmatic app root、mock REST + WebSocket、thread-safe store、row-level odds update、reconnect 與 scene/session cache。架構細節見 [`architecture.md`](architecture.md)，模組細節見 [`modules/`](modules/)。

## Source Layout

```text
OddsPulse/
├── OddsPulse/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── SceneDependencies.swift
│   ├── Matches/
│   │   ├── Model/
│   │   ├── View/
│   │   ├── ViewController/
│   │   └── ViewModel/
│   ├── Services/
│   ├── Stores/
│   └── Resources/MockData/
├── OddsPulseTests/
└── docs/
```

## Docs Map

| 文件 | 主題 | 閱讀時間 |
|:---|:---|:---|
| [`product.md`](product.md) | 題目需求、假設邊界、交付狀態 | 2 分鐘 |
| [`architecture.md`](architecture.md) | 架構分層、資料流、thread-safe 設計 | 5 分鐘 |
| [`workflow.md`](workflow.md) | build/test 指令與驗證注意事項 | 1 分鐘 |
| [`modules/live-odds.md`](modules/live-odds.md) | live odds data pipeline | 3 分鐘 |
| [`modules/matches-ui.md`](modules/matches-ui.md) | matches list UI 與 MVVM | 2 分鐘 |
| [`rules/interview-quality.md`](rules/interview-quality.md) | interview homework 品質規則 | 1 分鐘 |
| [`rules/uikit-programmatic-ui.md`](rules/uikit-programmatic-ui.md) | UIKit programmatic UI 規則 | 1 分鐘 |

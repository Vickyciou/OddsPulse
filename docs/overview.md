# Overview

本文件記錄 OddsPulse 的專案現況、source layout 與文件入口，作為進入 codebase 前的總覽。

## Project Snapshot

| 項目 | 現況 |
|:---|:---|
| Project type | iOS app interview homework |
| UI | UIKit programmatic UI |
| Architecture | MVVM |
| Core screen | Matches list with live odds updates |
| Data source | bundled JSON fixtures + mock WebSocket timer |
| State safety | `OddsStore` actor 持有 `Snapshot`，由 actor 保護 canonical match/odds state |
| Tests | XCTest 覆蓋 mapping、repository、snapshot、store、WebSocket、provider、ViewModel、reconnect policy |

## Current Implementation Status

| 範圍 | 現況 |
|:---|:---|
| Programmatic app root | `SceneDelegate` 建立 `UINavigationController` 與 `MatchesViewController` |
| Shared dependencies | `SceneDependencies` 持有 scene/session scope 的 `LiveOddsProviderProtocol` |
| Initial data load | `LiveOddsProvider` 呼叫 `RecordsRepository`；repository 平行呼叫 mock matches 與 odds services 並執行 mapping |
| Live odds feed | `LiveOddsProvider` 依賴 `OddsWebSocketServiceProtocol`；`MockOddsWebSocketService` 包裝 `MockOddsWebSocketClient`，client 以 `Timer` 產生 `AsyncStream<OddsWebSocketEvent>` |
| Thread-safe state | `OddsStore` actor 提供 snapshot 與 partial odds update，內部資料結構由 `Snapshot` 管理 |
| UI state | `MatchesViewModel` 將 provider events 轉成 view state 與 row update intent |
| Table updates | 初次載入使用 full reload；live odds update 使用 visible row-level reload |
| Reconnect | `ReconnectPolicy` 由 `MockOddsWebSocketService` 套用 retry limit 與 delay |
| Cache | scene/session in-memory cache，由 shared provider 與 store 保存 |

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

| 文件 | 主題 |
|:---|:---|
| [`product.md`](product.md) | 題目需求、scope、交付狀態 |
| [`architecture.md`](architecture.md) | 架構分層、資料流、thread-safe 設計 |
| [`workflow.md`](workflow.md) | 開發順序、build/test 指令、驗證注意事項 |
| [`modules/live-odds.md`](modules/live-odds.md) | live odds data pipeline |
| [`modules/matches-ui.md`](modules/matches-ui.md) | matches list UI 與 MVVM |
| [`rules/interview-quality.md`](rules/interview-quality.md) | interview homework 品質規則 |
| [`rules/uikit-programmatic-ui.md`](rules/uikit-programmatic-ui.md) | UIKit programmatic UI 規則 |

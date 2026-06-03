# Matches UI Module

本文件記錄 OddsPulse matches list UI 模組現況，包含 ViewController、ViewModel、row model mapping 與 row-level update。

## Module Scope

| 類別 | 主要型別 | 職責 |
|:---|:---|:---|
| ViewController | `MatchesViewController` | 建立 UIKit UI、綁定 ViewModel output、套用 table reload 或 row update |
| ViewModel | `MatchesViewModel` | 消費 `LiveOddsEvent`，管理畫面 state、rows 與 row index mapping |
| Cell | `MatchTableViewCell` | 呈現隊伍、賠率與比賽時間 |
| Row mapping | `MatchRowViewModelMapper`、`MatchRowViewModel` | 將 domain `MatchRecord` 轉成 UI display model |
| State | `MatchesViewState` | 表達 idle/loading/loaded/failed |

## MVVM Responsibilities

| Layer | 現況 |
|:---|:---|
| ViewController | 不直接打 API，不讀寫 store；只透過 closures 接收 ViewModel output |
| ViewModel | 不直接 connect WebSocket、不讀寫 `OddsStore`；只訂閱 `LiveOddsProviderProtocol.stream()` |
| Provider | 對 ViewModel 輸出 `LiveOddsEvent`，詳見 [`live-odds.md`](live-odds.md) |
| Cell | 接收 `MatchRowViewModel` 並設定 label text |

## State Flow

```text
MatchesViewController.viewDidLoad()
  -> bindViewModel()
  -> viewModel.start()
      -> Task { @MainActor in for await event in liveOddsProvider.stream() }
      -> handle(event)
          -> onStateChange
          -> onRowIndexesUpdated
          -> onFeedStatusChange
```

`MatchesViewModel` 是 `@MainActor`，畫面狀態與 callbacks 均在 main actor 上使用。

## Render States

| `MatchesViewState` | ViewController 行為 |
|:---|:---|
| `.idle` | 停止 loading，隱藏 message 與 table |
| `.loading` | `reloadData()` 清空 table，顯示 loading |
| `.loaded(rows)` | `reloadData()` 做初次完整載入，依 rows 是否為空顯示 table 或 empty message |
| `.failed(message)` | `reloadData()` 清空 table，顯示錯誤 message |

## Row-level Update Flow

```text
LiveOddsEvent.oddsUpdated(changedRecords:)
  -> MatchesViewModel.updateRows(from:)
      -> MatchRowViewModelMapper.makeRows(from:)
      -> use rowIndexByMatchID to update rows array
      -> emit onRowIndexesUpdated(updatedRowIndexes)
  -> MatchesViewController.renderRowUpdates(updatedRowIndexes:)
      -> filter visible indexPaths
      -> tableView.reloadRows(at:with:)
      -> log live update counts
```

目前 live odds update 不以整頁 `reloadData()` 作為主要機制；`reloadData()` 只用於 loading、loaded 與 failed 這類整體 state change。

## Formatting

`MatchRowViewModelMapper` 目前負責：

| 欄位 | 現況 |
|:---|:---|
| `startTimeText` | `DateFormatter`，locale `en_US_POSIX`，time zone `.current`，格式 `MMM d, HH:mm` |
| odds text | `NumberFormatter`，小數 2 位 |
| unavailable odds | 顯示 `--` |

## Diagnostics

`MatchesViewController` 使用 `OSLog` category `TableUpdate` 記錄：

| Log | 用途 |
|:---|:---|
| `logInitialReload(rowCount:)` | 記錄 initial/full reload 次數與 rows 數量 |
| `logLiveRowUpdate(updatedRowCount:visibleReloadCount:)` | 記錄 live update 影響 rows、visible reloads 與 offscreen skipped count |

## Tests

| Test file | 覆蓋範圍 |
|:---|:---|
| `MatchesViewModelTests.swift` | loading、records loaded、initial load failed、row update、unknown row、feed status、stream cancellation |
| `MatchRowViewModelMapperTests.swift` | unavailable odds 顯示 `--` |

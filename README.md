# OddsPulse

## 架構概要

OddsPulse 採用 UIKit + MVVM 架構，並將資料取得、狀態管理與即時更新責任拆分為獨立元件。

```text
MatchesViewController
    ↓
MatchesViewModel
    ↓
LiveOddsProvider
    ├── RecordsRepository
    │      ├── MatchesService
    │      ├── OddsService
    │      └── MatchRecordMapper
    │
    ├── OddsStore (actor)
    │      └── Snapshot
    │
    └── OddsWebSocketService
           └── OddsWebSocketClient
```

- MatchesViewController：負責 UI 顯示與使用者互動。
- MatchesViewModel：將資料轉換為畫面狀態與 Cell ViewModel。
- LiveOddsProvider：作為 ViewModel 的資料入口，負責 cache-first flow、資料刷新、Store 更新與 WebSocket 訂閱。
- RecordsRepository：負責取得 Matches 與 Odds API 資料並組合為 Domain Model。
- OddsStore：維護目前比賽與賠率狀態。
- OddsWebSocketService：負責 WebSocket 連線、重連與即時賠率更新。

## Data Flow

### Initial Load

```text
Read Snapshot
    ↓
Cache Exists?
├─ Yes → Render Cached Records
└─ No  → Show Loading

↓
Refresh Records
│
├─ Success
│  ↓
│ Replace Store
│  ↓
│ Render Latest Records
│  ↓
│ Start WebSocket
│
└─ Failure
   ↓
   Cached Records Exist?
   ├─ Yes → Keep Cached Records
   └─ No  → Show Failed Empty State
```

### Live Odds Update

```text
WebSocket Event
        ↓
    OddsUpdate
        ↓
  OddsStore (actor)
        ↓
  Changed Records
        ↓
     ViewModel
        ↓
 Affected Row Indexes
        ↓
  reloadRows(at:)
```

只有實際變更的比賽資料會通知 UI 更新，因此即時賠率更新時僅重新載入受影響的 Cell，不會整頁 reload。

---

## Swift Concurrency 使用場景

本專案使用 Swift Concurrency 作為主要非同步模型，未使用 Combine。

- async/await：REST API 呼叫。
- async let：平行取得 Matches 與 Odds 資料。
- AsyncStream：Provider 與 WebSocket 的事件串流。
- Task：資料刷新、WebSocket 監聽與重連流程。
- @MainActor：保護 UI 狀態與 callback 更新。

---

## Thread-safe 資料存取

OddsStore 採用 actor 實作，作為共享資料的唯一存取入口。

所有比賽與賠率資料更新皆透過：

- snapshot()
- replaceRecords(_:)
- applyOddsUpdates(_:)

進行，避免多執行緒同時修改資料造成 race condition。

```text
OddsUpdate
    ↓
OddsStore (actor)
    ↓
Snapshot Mutation
    ↓
Changed Records
    ↓
ViewModel
    ↓
Reload Affected Rows Only
```

此外：

- LiveOddsProvider 與 MatchesViewModel 使用 @MainActor 保護 UI 相關狀態。
- WebSocket DTO 會先於 OddsWebSocketService 轉換為 Domain OddsUpdate。
- Store 與 Snapshot 不依賴 API DTO 或 WebSocket DTO。
- UI 不直接讀寫 Store，所有資料流皆透過 Provider 協調。

---

## 額外實作

- Cache-first rendering
- WebSocket 自動重連
- Unit Tests
- Architecture Documentation

# Architecture

## Overview

deree is built with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) and Swift 6 strict concurrency.

## Feature Composition

```
AppReducer (root)
  ├── ClipboardFeature   -- clipboard polling, image capture, storage I/O
  └── PanelFeature       -- panel visibility state
```

- **AppReducer** composes child features via `Scope` and handles app lifecycle / menu bar actions.
- **ClipboardFeature** owns the image list, polling lifecycle (`ContinuousClock` timer), and pasteboard read/write.
- **PanelFeature** manages panel show/hide state.

## Dependencies

TCA `@Dependency` で副作用を注入。テスト時は `TestStore` + `TestClock` で差し替え。

| Dependency | Role |
|-----------|------|
| `ClipboardClient` | `NSPasteboard` の read/write/changeCount ラッパー。`@MainActor` 隔離 |
| `StorageClient` | ディスクへの画像保存/読込/削除。`StorageActor` (custom global actor) で隔離 |
| `ContinuousClock` | TCA 組み込み。ポーリングタイマー。テストでは `ImmediateClock` / `TestClock` |

## Data Flow

```
User copies image in any app
        │
        ▼
ClipboardFeature: timerTicked (every 0.5s)
        │  changeCount changed? → readImage from pasteboard
        ▼
StorageClient.save(imageData)
        │  → full PNG to ~/Library/Application Support/deree/full/
        │  → thumbnail (200px) to ~/Library/Application Support/deree/thumb/
        │  → update metadata.json
        ▼
State.images updated → SwiftUI auto-refresh
        │
        ▼
New image appears in panel
```

### Self-Capture Prevention

When the app copies an image back to the pasteboard via `copyImageToPasteboard`, it updates `lastChangeCount` after the write. The next timer tick sees the same count and skips it.

## NSPanel Integration

Pure SwiftUI cannot create a non-activating floating panel. `FloatingPanel` is an `NSPanel` subclass with:

- `.nonactivatingPanel` — does not steal focus
- `.floating` level — stays above normal windows
- `.canJoinAllSpaces` — visible on all desktops

TCA State is the single source of truth. `AppDelegate` observes `store.panel.isPanelVisible` and calls `panel.orderFront/orderOut` accordingly. The panel's close button sends `.panel(.hidePanel)` back into the store.

## Swift 6 Concurrency

The project uses Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`).

| Layer | Isolation |
|-------|----------|
| App / UI / AppKit | `@MainActor` |
| ClipboardClient (NSPasteboard) | `@MainActor` (`MainActor.assumeIsolated`) |
| StorageClient (file I/O) | `@StorageActor` (custom global actor) |
| Domain types | `Sendable` structs |

## Storage Layout

```
~/Library/Application Support/deree/
├── metadata.json              # IdentifiedArrayOf<ClipboardImage> (newest first)
├── full/
│   └── {uuid}.png             # full-size PNG
└── thumb/
    └── {uuid}.png             # thumbnail (max 200px width)
```

- Maximum 50 images. Oldest are auto-deleted on save.
- Metadata uses `deferredToDate` encoding for lossless `Date` round-trips.

## Project Management

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). `*.xcodeproj` is gitignored.

# Architecture

## Overview

deree is built with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture) and Swift 6 strict concurrency. All warnings are treated as errors.

## Feature Composition

```
AppReducer (root)
  ├── ClipboardFeature   -- clipboard polling, image capture, storage I/O, thumbnail cache
  └── PanelFeature       -- panel visibility state
```

- **AppReducer** composes child features via `Scope` and handles app lifecycle / menu bar actions.
- **ClipboardFeature** owns the image list, thumbnail cache, polling lifecycle (`ContinuousClock` timer), and pasteboard read/write.
- **PanelFeature** manages panel show/hide state.

## Dependencies

TCA `@Dependency` で副作用を注入。テスト時は `TestStore` + `TestClock` で差し替え。

| Dependency | Role |
|-----------|------|
| `ClipboardClient` | `NSPasteboard` の read/write/changeCount ラッパー。`readImage` はファイルURL（Finder Cmd+C）にも対応。`writeImage` は `async throws` |
| `StorageClient` | ディスクへの画像保存/読込/削除。`save` は `SaveResult` を返し、保存した画像と eviction で削除された画像IDを含む |
| `ContinuousClock` | TCA 組み込み。ポーリングタイマー。テストでは `ImmediateClock` / `TestClock` |

ビジネスパラメータは `StorageConstants` に集約（`maxImageCount = 50`, `thumbnailMaxWidth = 200`）。

## Error Design

```
FeatureError (Reducer → State)
  ├── .storageFailed(StorageError)
  ├── .clipboardFailed(ClipboardError)
  └── .unexpectedError(String)

StorageError
  ├── .invalidImageData
  ├── .imageNotFound(UUID)
  └── .thumbnailGenerationFailed

ClipboardError
  └── .invalidImageData
```

全ての `.run` Effect は `do/catch` でエラーを捕捉し、型別 catch で適切な `FeatureError` に変換。サムネイルロード失敗は `os.Logger` で警告のみ（フォールバック表示）。

## Data Flow

```
User copies image in any app
        │
        ▼
ClipboardFeature: timerTicked (every 0.5s)
        │  changeCount changed?
        │  → readImage (file URL first, then direct NSImage)
        ▼
StorageClient.save(imageData) → SaveResult
        │  → CGImageSource からメタデータ解析 + サムネイル生成
        │  → full PNG to ~/Library/Application Support/deree/full/
        │  → thumbnail to ~/Library/Application Support/deree/thumb/
        │  → metadata.json 更新 + 50件超過分を eviction
        │  → 失敗時はファイルをロールバック削除
        ▼
State.images + State.thumbnails 更新 → SwiftUI auto-refresh
        │
        ▼
New image appears in panel
```

### Thumbnail Generation

`CGImageSourceCreateThumbnailAtIndex` (ImageIO) を使用。最大幅 200px にリサイズし、PNG にエンコード。CGImageSource は寸法解析と共有して二重パースを回避。

### Self-Capture Prevention

When the app copies an image back to the pasteboard via `copyImageToPasteboard`, it updates `lastChangeCount` after the write. The next timer tick sees the same count and skips it.

## NSPanel Integration

Pure SwiftUI cannot create a non-activating floating panel. `FloatingPanel` is a `@MainActor` `NSPanel` subclass with:

- `.nonactivatingPanel` — does not steal focus
- `.floating` level — stays above normal windows
- `.canJoinAllSpaces` — visible on all desktops
- `slideIn()` / `slideOut()` — right-edge slide animation (ease-out 0.2s / ease-in 0.15s)

TCA State is the single source of truth. `AppDelegate` observes `store.panel.isPanelVisible` and calls `slideIn/slideOut` accordingly. パネルはフォーカス消失時（`didResignActiveNotification`）に自動で隠れる。

### Menu Bar Integration

`NSStatusItem` を直接使用（SwiftUI `MenuBarExtra` ではない）。左クリックでパネルをトグル、右クリックで Quit メニュー。パネル表示中はアイコンが fill になる。

## Swift 6 Concurrency

The project uses Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`).

| Layer | Isolation |
|-------|----------|
| App / UI / AppKit / FloatingPanel | `@MainActor` |
| ClipboardClient (NSPasteboard) | `@MainActor` (`MainActor.assumeIsolated` / `MainActor.run`) |
| LiveStorage (file I/O) | `@StorageActor` (class-level global actor isolation) |
| Domain types | `Sendable` structs |

## Storage Layout

```
~/Library/Application Support/deree/
├── metadata.json              # [ClipboardImage] as JSON (newest first)
├── full/
│   └── full_{uuid}.png        # full-size PNG
└── thumb/
    └── thumb_{uuid}.png       # thumbnail (max 200px width)
```

- Maximum 50 images (`StorageConstants.maxImageCount`). Oldest are auto-deleted on save.
- File names are derived from UUID via `ClipboardImage.fullFileName(for:)` / `thumbFileName(for:)` (single source of truth).
- `delete` writes metadata first, then removes files (safe ordering).
- Eviction file removal failures are logged but don't block save.

## Project Management

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). `*.xcodeproj` is gitignored.

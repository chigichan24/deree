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

Side effects are injected via TCA `@Dependency`. Tests swap them out using `TestStore` + `TestClock`.

| Dependency | Role |
|-----------|------|
| `ClipboardClient` | Wraps `NSPasteboard` read/write/changeCount. `readImage` supports both direct image data and file URLs (Finder Cmd+C). `writeImage` is `async throws` |
| `StorageClient` | Disk-based image save/load/delete. `save` returns `SaveResult` containing the saved image and evicted image IDs |
| `ContinuousClock` | Built-in TCA clock for polling timer. Replaced with `ImmediateClock` / `TestClock` in tests |

Business parameters are centralized in `StorageConstants` (`maxImageCount = 50`, `thumbnailMaxWidth = 200`).

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

All `.run` Effects use `do/catch` with typed catch clauses to convert errors into the appropriate `FeatureError` variant. Thumbnail load failures are logged via `os.Logger` and fall back to a placeholder display.

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
        │  → parse metadata + generate thumbnail via shared CGImageSource
        │  → full PNG to ~/Library/Application Support/deree/full/
        │  → thumbnail to ~/Library/Application Support/deree/thumb/
        │  → update metadata.json + evict images exceeding 50
        │  → rollback written files on failure
        ▼
State.images + State.thumbnails updated → SwiftUI auto-refresh
        │
        ▼
New image appears in panel
```

### Thumbnail Generation

Uses `CGImageSourceCreateThumbnailAtIndex` (ImageIO) to resize to a max width of 200px and encode as PNG. The `CGImageSource` is shared with dimension parsing to avoid decoding the image data twice.

### Self-Capture Prevention

When the app copies an image back to the pasteboard via `copyImageToPasteboard`, it updates `lastChangeCount` after the write. The next timer tick sees the same count and skips it.

## NSPanel Integration

Pure SwiftUI cannot create a non-activating floating panel. `FloatingPanel` is a `@MainActor` `NSPanel` subclass with:

- `.nonactivatingPanel` — does not steal focus
- `.floating` level — stays above normal windows
- `.canJoinAllSpaces` — visible on all desktops
- `slideIn()` / `slideOut()` — right-edge slide animation (ease-out 0.2s / ease-in 0.15s)

TCA State is the single source of truth. `AppDelegate` observes `store.panel.isPanelVisible` and calls `slideIn/slideOut` accordingly. The panel auto-hides when the app loses focus (`didResignActiveNotification`).

### Menu Bar Integration

Uses `NSStatusItem` directly (not SwiftUI `MenuBarExtra`). Left-click toggles the panel, right-click shows a Quit menu. The icon switches between outline and fill to indicate panel state.

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

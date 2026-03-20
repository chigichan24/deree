# deree

macOS menu bar app that keeps a visual history of images you copy to the clipboard.

## Features

- Clipboard image history displayed in a floating side panel on the right edge of the screen
- Automatically captures images when you copy them in any app
- Click a thumbnail to copy it back to the clipboard
- Keeps the last 50 images, older ones are automatically cleaned up
- Panel stays visible across all Spaces without stealing focus
- Show/hide the panel from the menu bar icon or with Cmd+Shift+D
- Persists history across app restarts
- Runs as a menu bar app (no Dock icon)

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project deree.xcodeproj -scheme deree -destination 'platform=macOS' -skipMacroValidation build

# Run tests
xcodebuild -project deree.xcodeproj -scheme dereeTests -destination 'platform=macOS' -skipMacroValidation test
```

Or open `deree.xcodeproj` in Xcode after running `xcodegen generate`.

> **Note:** `-skipMacroValidation` is required because TCA uses Swift macros from SPM packages.

## Usage

1. Launch the app -- an icon appears in the menu bar
2. Copy any image in any app (screenshot, browser, Figma, etc.)
3. The image appears in the side panel
4. Click a thumbnail to copy it back to the clipboard
5. Use the menu bar icon to show/hide the panel

## Data Storage

Images are stored in `~/Library/Application Support/deree/`. To reset all data, quit the app and delete that directory.

## Docs

- [Architecture](docs/architecture.md) -- TCA feature composition, data flow, concurrency model

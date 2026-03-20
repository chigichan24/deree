<p align="center">
  <img src="docs/icon.png" width="128" alt="deree icon">
</p>

# deree

macOS menu bar app that keeps a visual history of images you copy to the clipboard.

## Features

- Clipboard image history displayed in a floating side panel on the right edge of the screen
- Automatically captures images from screenshots, app copies, and Finder file copies (Cmd+C)
- Click a thumbnail to copy it back to the clipboard
- Keeps the last 50 images, older ones are automatically cleaned up
- Panel slides in/out from the right edge with animation
- Click the menu bar icon to toggle the panel instantly
- Panel auto-hides when you switch to another app
- Persists history across app restarts
- Runs as a menu bar app (no Dock icon)

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Install

```bash
brew install xcodegen
git clone https://github.com/chigichan24/deree.git && cd deree
xcodegen generate
xcodebuild -project deree.xcodeproj -scheme deree -configuration Release \
  -destination 'platform=macOS' -skipMacroValidation \
  -derivedDataPath build
cp -r build/Build/Products/Release/deree.app /Applications/
open /Applications/deree.app
```

To launch at login, add deree in System Settings → General → Login Items.

## Development

```bash
xcodegen generate

# Build (debug)
xcodebuild -project deree.xcodeproj -scheme deree -destination 'platform=macOS' -skipMacroValidation build

# Run tests
xcodebuild -project deree.xcodeproj -scheme dereeTests -destination 'platform=macOS' -skipMacroValidation test
```

Or open `deree.xcodeproj` in Xcode after running `xcodegen generate`.

> **Note:** `-skipMacroValidation` is required because TCA uses Swift macros from SPM packages.

All warnings are treated as errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `GCC_TREAT_WARNINGS_AS_ERRORS`).

## Usage

1. Launch the app -- an icon appears in the menu bar (may be hidden behind the notch on MacBooks)
2. Copy any image (screenshot, browser, Figma, Finder Cmd+C on image files, etc.)
3. Left-click the menu bar icon to slide in the panel
4. Click a thumbnail to copy it back to the clipboard
5. Left-click the icon again, or switch to another app, to slide the panel away
6. Right-click the menu bar icon to quit

## Data Storage

Images are stored in `~/Library/Application Support/deree/`. To reset all data, quit the app and delete that directory.

## Docs

- [Architecture](docs/architecture.md) -- TCA feature composition, data flow, concurrency model

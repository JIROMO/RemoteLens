# RemoteLens

RemoteLens is a small macOS menu bar app that makes a Mac easier to control from a phone over remote desktop tools such as Chrome Remote Desktop.

It switches the display into a phone-friendly layout, so text and UI controls are larger and easier to tap on a small screen. Everything runs locally on your Mac. RemoteLens does not use network access, telemetry, or external services.

## Features

- Menu bar app for quick display switching
- Portrait mode for using a phone vertically
- Landscape remote mode for wider phone or tablet use
- Three readable scale presets
- One-click restore to the original display mode
- Automatic rollback when a mode switch fails
- Safety panel and floating restore button for portrait mode
- Optional launch at login

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools

RemoteLens uses CoreGraphics display APIs. Portrait mode also uses the private `CGVirtualDisplay` API, so this project is intended for local builds and direct distribution, not Mac App Store submission.

## Build

```bash
./build.sh            # build/RemoteLens.app を作成
./build.sh install    # ビルドして /Applications にインストール
```

The app is signed with an ad-hoc signature by `build.sh`.

## Usage

1. Launch RemoteLens.
2. Open the menu bar icon.
3. Choose a remote mode:
   - `リモートモード（縦長・スマホ縦持ち）`: creates a portrait virtual display and mirrors the built-in display to it.
   - `リモートモード（横長）`: switches the current display to a lower-resolution HiDPI mode.
4. Connect from your phone using your remote desktop app.
5. Choose `通常モードに戻す` to restore your original display mode.

## Presets

| Preset | Landscape target | Portrait target | Use case |
|---|---|---|---|
| 文字最大 | 960 x 600 | 600 x 960 | Maximum readability |
| バランス | 1024 x 640 | 640 x 1024 | Default balance |
| 作業領域広め | 1280 x 800 | 800 x 1280 | More workspace |

Actual display modes depend on your Mac. RemoteLens picks the closest available HiDPI mode for the selected preset.

## How Portrait Mode Works

Portrait mode creates a temporary portrait virtual display with `CGVirtualDisplay`, then mirrors the built-in display to that virtual display. Remote desktop software sees the portrait layout, which fits a phone held vertically.

The virtual display only exists while RemoteLens is running. If the app quits or crashes, macOS removes the virtual display and restores the display configuration.

## Safety

- The previous display mode is saved before switching.
- Failed switches roll back automatically.
- Portrait mode shows a confirmation panel and automatically restores if it is not confirmed.
- A floating restore button remains available while portrait mode is active.
- The app performs no network communication.

## Known Limitations

- Portrait mode depends on a private macOS API and may break on future macOS versions.
- Available HiDPI modes vary by Mac model and display.
- Multi-display support is currently focused on the main display.
- This project is currently optimized for Japanese UI labels.

## Project Structure

```
Sources/RemoteLens/
  RemoteLensApp.swift   App entry point
  MenuContent.swift    Menu bar UI
  AppState.swift       UI state and launch-at-login handling
  DisplayManager.swift Display mode switching and restore logic
Sources/VirtualDisplayBridge/
  PCTVirtualDisplay.m  Objective-C wrapper for CGVirtualDisplay
Resources/
  AppIcon.icns         App icon
  Info.plist           App bundle metadata
build.sh               Build, bundle, sign, and install script
```

## License

No license has been added yet.

# Architecture

KeepMirror is a menu bar camera mirror app built with AppKit + SwiftUI + AVFoundation.

## Runtime overview

- `AppDelegate` creates the app environment at launch.
- `AppEnvironment.makeEnvironment()` wires dependencies.
- `MirrorController` coordinates app-level behavior.
- `StatusItemController` owns the menu bar item, popover lifecycle, and right-click menu.

The app runs as an accessory app (`LSUIElement = true`), so there is no Dock icon.

## Core components

### `MirrorController`

Main orchestration layer.

Responsibilities:

- launch flow and onboarding gate
- start/stop camera session requests
- capture photo workflow (including save panel and bookmark persistence)
- settings window routing
- launch-at-login state syncing
- hotkey manager integration

### `MirrorSettings`

`ObservableObject` backed by `UserDefaults`.

Persists preferences for:

- mirror size, selected camera, mirror flip, quality preset
- capture save bookmark, format, countdown, clipboard/finder behavior
- mic check enablement, selected mic, sensitivity
- notch hover behavior
- start at login, capture flash
- onboarding completion
- global hotkey key code and modifiers

### `CameraManager`

Owns `AVCaptureSession` and `AVCaptureVideoPreviewLayer`.

Key design points:

- session mutation happens on a dedicated serial `sessionQueue`
- published state is bridged to `@MainActor`
- supports camera/mic device enumeration and live switching
- supports still capture through `AVCapturePhotoOutput`
- computes mic level from captured audio buffers

### `StatusItemController`

Owns `NSStatusItem` and `NSPopover`.

Responsibilities:

- click routing (left click toggle popover, right click context menu)
- camera lifecycle on popover open/close
- mic monitor lifecycle in popover mode
- popover watchdog restart path for camera startup hiccups
- menu bar icon visibility rules for notch mode

### `NotchHoverMonitor`

Tracks global mouse movement and detects cursor entry/exit in a notch trigger zone.

- no keyboard interception
- no click interception
- no high-privilege permissions

### `NotchPanelController`

Manages a reusable non-activating floating panel under the notch.

Responsibilities:

- animated show/hide
- panel camera lifecycle and mic monitor lifecycle
- notch-only compact mirror rendering path

### `SettingsWindowManager`

Keeps one stable `NSHostingController` for settings.

This avoids SwiftUI state reset each time settings is opened.

### `GlobalHotkeyManager`

Uses Carbon `EventHotKey` registration for a global toggle hotkey.

Default shortcut: Command+Shift+M.

## Data and permissions model

- No app account system
- No network dependency for core behavior
- Camera permission is required for mirror preview and captures
- Microphone permission is optional for live mic level meter

KeepMirror does not require:

- Accessibility
- Input Monitoring
- Screen Recording

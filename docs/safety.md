# Safety

KeepMirror is designed to be predictable and transparent.

## Camera lifecycle safety

- Camera starts when mirror UI is opened.
- Camera stops when mirror UI is closed.
- App termination triggers camera stop as a final cleanup step.

## Mic lifecycle safety

- Mic level monitoring is optional and user-controlled.
- Mic monitor is started/stopped with mirror UI lifecycle when enabled.
- Settings "Test Mic" mode has explicit start/stop controls.

## Capture safety

- First capture asks where to save photos.
- Save directory is remembered via a scoped bookmark.
- Optional clipboard/finder actions are user toggles.

## Permission transparency

KeepMirror exposes permission state in Settings and provides direct links to relevant System Settings pages when access is denied.

## No stealth background agent

KeepMirror is a menu bar app. When it is not running, no camera/mic mirror session is active.

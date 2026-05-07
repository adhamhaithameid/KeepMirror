<p align="center">
  <img src="KeepMirror/Resources/brand-mark.png" width="128" alt="KeepMirror app icon" />
</p>

<h1 align="center">KeepMirror</h1>

<p align="center">
  <strong>A fast menu bar mirror for macOS with one-tap snapshots and optional mic level check.</strong>
</p>

<p align="center">
  <a href="https://github.com/adhamhaithameid/KeepMirror/releases">Download</a> ·
  <a href="docs/install-from-github.md">Install Guide</a> ·
  <a href="docs/faq.md">FAQ</a> ·
  <a href="docs/privacy.md">Privacy</a>
</p>

<p align="center">
  <a href="https://buymeacoffee.com/adhamhaithameid">
    <img alt="Buy Me a Coffee" src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=000000" />
  </a>
</p>

---

## What is KeepMirror?

KeepMirror is a native macOS menu bar app that opens a floating camera mirror instantly.

It is designed for quick real-world moments:

- check your camera framing before a call
- quickly inspect your look before recording
- monitor your microphone level while speaking
- capture clean snapshots without opening a full camera app

The app stays lightweight, local, and out of the way.

## Core features

- Fast popover mirror from the menu bar
- One-tap (or Space key) photo capture
- Optional capture countdown (Off, 3s, 5s)
- Save as PNG, JPEG, or HEIF
- Optional copy to clipboard and reveal in Finder after capture
- Optional live mic level badge with sensitivity controls
- Notch hover mode on notch-enabled Macs
- Global hotkey (default: Command+Shift+M)
- Start at login support

## How it works

1. Launch `KeepMirror.app`.
2. Click the menu bar icon to open the mirror.
3. Tap the preview (or press Space) to capture a photo.
4. Use the settings gear for camera, capture, mic, notch, and hotkey preferences.

Right-click the menu bar icon for quick actions: open mirror, open settings, quit.

## Permissions

KeepMirror uses only the permissions needed for its features:

- Camera: required for mirror preview and captures
- Microphone: optional, only for mic level meter

KeepMirror does not request Accessibility, Input Monitoring, or Screen Recording.

See [Permissions](docs/permissions.md) for details.

## Privacy

KeepMirror runs locally on your Mac and does not include analytics, tracking, or account services.

See [Privacy](docs/privacy.md).

## Documentation

- [Install Guide](docs/install-from-github.md)
- [FAQ](docs/faq.md)
- [Safety](docs/safety.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Permissions](docs/permissions.md)
- [Architecture](docs/architecture.md)
- [Manual Testing](docs/manual-testing.md)
- [Uninstall](docs/uninstall.md)
- [Future Features](future-features.md)

## Build and release helpers

- `./script/build_and_run.sh`
- `./script/run_logic_checks.sh`
- `./script/run_release_checks.sh`
- `./script/make_installers.sh`
- `./script/notarize_release.sh`

## License

Source-available under [PolyForm Noncommercial 1.0.0](LICENSE.md).

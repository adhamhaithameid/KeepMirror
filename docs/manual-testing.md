# Manual Testing

## Launch and menu bar behavior

1. Launch `KeepMirror.app`.
2. Confirm icon appears in the menu bar.
3. Left-click icon.
4. Confirm mirror popover opens and camera light turns on.
5. Left-click icon again.
6. Confirm popover closes and camera light turns off.

## Right-click context menu

1. Right-click icon.
2. Confirm menu shows:
   - Open Mirror
   - Settings
   - Quit KeepMirror
3. Click Open Mirror and confirm popover opens.
4. Click Settings and confirm settings window opens.

## Camera permission flow

1. Revoke Camera permission for KeepMirror.
2. Open popover.
3. Confirm camera permission prompt UI appears.
4. Grant permission and reopen popover.
5. Confirm live preview appears.

## Capture workflow

1. Open mirror popover.
2. Tap preview.
3. On first capture, confirm save prompt appears.
4. Save image and confirm file exists.
5. Trigger capture again and confirm it saves directly to remembered folder.

## Capture settings

1. In Settings -> Capture, set format to PNG.
2. Capture and confirm `.png` output.
3. Repeat for JPEG and HEIF.
4. Enable countdown (3s), capture, confirm countdown appears.
5. Enable Copy to Clipboard, capture, confirm image is on clipboard.
6. Enable Reveal in Finder, capture, confirm Finder opens selected file.

## Mic check

1. In Settings -> Mic Check, enable mic check.
2. If needed, grant microphone permission.
3. Click Test Now and speak.
4. Confirm live meter reacts.
5. Change sensitivity and confirm responsiveness changes.
6. Stop test and confirm mic monitor stops.

## Notch mode (notch-capable Macs only)

1. Enable Open Mirror from Notch.
2. Hover cursor into notch trigger area.
3. Confirm floating notch panel appears.
4. Move cursor out and confirm panel hides.
5. Optionally enable Hide Menu Bar Icon and confirm icon visibility updates.

## Hotkey

1. Use default Command+Shift+M.
2. Confirm it toggles the mirror popover.
3. Record a custom hotkey in Settings.
4. Confirm new hotkey toggles and old hotkey no longer does.

## Start at login

1. Enable Start at Login.
2. Quit app.
3. Sign out and sign back in (or reboot).
4. Confirm KeepMirror starts automatically.

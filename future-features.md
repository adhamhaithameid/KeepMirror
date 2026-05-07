# Future Features

Planned ideas for future implementation, grouped by area:

## Mirror Experience

- Make the mirror size customizable by users.
- Add a mirror launch-position option: pop out from the menu bar icon or pop out from the screen center (camera position).
- Add an option to use full width and full height for the mirror.
- Make full width/full height the default mirror preview mode.
- Add a mode with no widgets that uses hover to always zoom in the mirror preview.
- Add a zoom feature.
- Introduce a full liquid-design UI overhaul, especially for the mirror experience.

## Widgets and Reactions

- Implement widgets as a proof of concept.
- Add more widgets to put on the mirror.
- Add 8 widget placement options: top-left, top-center, top-right, center-left, center-right, bottom-left, bottom-center, and bottom-right.
- Keep widgets hidden by default and only reveal them when hovering over the mirror.
- Add reaction toggle settings and ship reactions as icon widgets users can enable/disable at any time.

## Icons and Branding

- Change the icons in the menu bar.
- Make different icon designs so users can choose their preferred icon set.

## Capture and Output

- Change the output of the image captured by the app.
- Add custom dates, fonts, and styles to captured images.

## Settings and Navigation

- Add a settings option to show the Dock icon.
- Re-arrange Settings with a left-side navbar/table-of-contents style layout (similar to Notion), with each feature section listed as a title.

## Automation and Smart Triggers

- Add an auto-notch trigger and test coverage for it.

## Onboarding and Quality

- Add cool onboarding.
- Add more test suites/plans.

## Security and Performance Hardening

- Add stricter privacy controls for camera/microphone usage visibility and permission-state handling.
- Harden file output paths and sandbox-related error handling for capture/save flows.
- Add crash-resilience and recovery logic around camera session start/stop and device switching.
- Optimize mirror rendering pipeline for lower CPU/GPU usage during idle and hover states.
- Reduce memory churn during live preview, capture, and widget animations.
- Add performance benchmarks and regression checks for launch time, frame rate, and memory.

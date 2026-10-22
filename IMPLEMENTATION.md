# MonitorLight implementation

Approved design: a macOS menu bar application controlling external display hardware brightness through DDC/CI. Use the locally verified, MIT-licensed m1ddc helper; never control an unselected/default display.

- [x] Add a Swift package with a separately testable core: display parsing, brightness normalization and input clamping.
- [x] Embed a serial, time-limited Process adapter for m1ddc; report readback failures instead of displaying fabricated success.
- [x] Add an AppKit status item and SwiftUI popover with display selection, slider, presets, refresh and hardware status.
- [x] Register Command-Option-Up/Down hotkeys and refresh display inventory after hotplug or wake.
- [x] Build an ad-hoc signed standalone app containing the helper and MIT license; provide source and ZIP.
- [x] Run core tests, build, exercise hardware change/readback/restore, and verify the running app and menu panel.

Defaults: target only external displays; presets 15%, 45%, 80%; shortcut step 5%; do not change brightness on launch or automatically restore a saved level; no login item, no network calls, no administrator or accessibility permission required for these Carbon hotkeys.

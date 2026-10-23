# Cold/warm control implementation plan

**Goal:** Add relative hardware RGB warmth control, persistent original-color restoration, and independent failure reporting.

**Architecture:** Pure RGB types and interpolation in BrightnessCore; serial verified DDC operations and rollback in DDCClient; per-display baseline storage and debounce in MonitorModel; existing SwiftUI styling in PanelView.

**Tech stack:** Swift, SwiftUI, AppKit, XCTest, m1ddc.

1. Add `ColorTemperatureTests.swift`: validate malformed channels; verify baseline `[80,70,60]`, warm `[80,63,39]`, cool `[52,63,60]`, zero and nonfinite recovery, Codable round trip, and invalid persisted data.
2. Run `swift test --scratch-path /tmp/monitorlight-color-build --build-system native` and observe missing types. Implement validated `RGBGain` and `ColorReading`, interpolation and tolerance; rerun tests.
3. Add DDC `readColor` and `setColor`: explicit UUID, three current/max readings, writes then readback; on any failure restore all pre-write channels individually and verify rollback. Surface rollback failure distinctly.
4. Update model: independent color availability/message, read-only refresh, baseline saved before first write keyed by UUID, debounced serialized writes, prohibit switching target during operations, restore from saved baseline after checking maximum values.
5. Add warm/neutral/cool slider, presets, restore button and capability explanation to PanelView; maintain existing appearance.
6. Run tests and `bash build.sh`; inspect bundled signature, run app and verify minimal hardware shift then restore if RGB supported. Do not change picture modes.
7. Update README/VERIFICATION and application version, package downloads and updated screenshot. Publish only MonitorLight files through authenticated GitHub connector, using expected branch SHA and preserving unrelated remote files. Verify public artifacts and CI.

Execution: inline in the current conversation, as requested by the user. Existing parent repository contains unrelated untracked work; no broad git add or branch reset. Changes are restricted to the standalone MonitorLight output folder and remote repository.

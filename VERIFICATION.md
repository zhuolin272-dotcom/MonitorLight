# Verification · 2026-10-23

- Swift core tests: 4 passed, 0 failures.
- Release build: passed for arm64 macOS.
- App and bundled helper ad-hoc signature verified in the clean staging directory.
- HKC G27M7Pro hardware read maximum: 100.
- Direct hardware probe: original 0 → write 3 → readback 3 → restored 0.
- Packaged app self-test: preset 15 → readback 15; increase 5 → readback 20; decrease 5 → readback 15; restored 0.
- Both Carbon global hotkeys registered successfully. Synthetic key events delivered directly to Finder did not exercise the system-global hotkey path; physical-key behavior is not independently verified.
- SwiftUI panel rendered to `MonitorLight-preview.png` and visually checked.
- Application launched successfully and remained running as a menu bar application.
- Hotplug and wake handlers are implemented; unplug/replug and a full sleep cycle were not performed.

No brightness change remains after verification. No unrelated project files were modified.

The distributable is locally ad-hoc signed, not Apple-notarized. The ZIP omits Finder/iCloud extended attributes that can interfere with signature inspection inside a synced Documents directory.

# Verification · 2026-10-23

- 1.0 Swift core tests: 4 passed, 0 failures (historical brightness verification).
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

## 1.1 cold/warm feature

- Swift tests: 12 passed, 0 failures (10 core/transaction tests plus 2 model-state regressions). Release arm64 build and staged app/helper ad-hoc signature verification passed.
- Added validated RGB channel types, relative warm/cool interpolation, Codable baseline validation, channel-range checks, readback verification and best-effort rollback.
- Added tests for neutral restoration, clamping/nonfinite inputs, unequal channel maxima, partial write failure, ignored writes, unconfirmed rollback, successful transaction and range mismatch before writes.
- Review found and regression tests reproduced a canceled warmth request leaving an optimistic slider value, and inventory failure retaining stale color capability. Both are fixed: superseded controls reset to confirmed values and failed detection clears color availability.
- HKC G27M7Pro: RGB maximum `[100, 100, 100]`, original `[44, 44, 50]`. Packaged app attempted a small warm adjustment; readback rejected the target in the current picture mode. Rollback and final restoration both confirmed `[44, 44, 50]`. No automatic HDR/picture-mode change was performed.
- Hardware color test therefore did **not** pass. The feature must not be advertised as working on this monitor's current mode. Brightness support is independent.
- A repeat test encountered an invalid/transient RGB reply; a subsequent direct read confirmed original `[44, 44, 50]` with maxima `[100, 100, 100]`. RGB read reliability is therefore also mode/hardware dependent.
- Panel screenshot updated and visually checked; persistence is implemented, but restart recovery, real multi-monitor operation and unplugging during RGB writes have not been physically exercised.

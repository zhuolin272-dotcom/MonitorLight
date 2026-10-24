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

## 1.1.1 local diagnostic build

- Reproduced a popover spanning the boundary between vertically arranged screens: old CG window bounds `(875, 859, 366, 594)` crossed the primary screen's 1080-point bottom edge.
- Added explicit content measurement, fixed viewport with vertical scrolling, selection of the screen containing the menu-bar anchor, and window-frame clamping to its visible bounds.
- Actual new AppKit diagnostic: anchor `{{1037, -31}, {22.5, 30}}`, target visible frame `{{159, -917}, {1512, 884}}`, final window `{{865, -662}, {366, 621}}`; `contained=true`. User-visible confirmation is still required; offscreen view captures alone do not verify onscreen visibility.
- 15 tests pass, including negative-origin screen geometry, oversized windows, and unverified color default guard; arm64 release build and staged signature verification pass.
- RGB raw reply trace was added behind `MONITORLIGHT_DDC_TRACE`. Read-only probes returned matching requested VCP IDs `0x16`, `0x18`, `0x1a`, values `[44, 44, 50]`. This rules out swapped reply IDs for those probes, not incorrect physical color behavior.
- Uncalibrated color writes now require an explicit experimental opt-in. Restore original remains available. Readback status now distinguishes numeric confirmation from actual color calibration.
- Hardware RGB direction and accurate color temperature remain unresolved pending user-observed channel tests. No hardware colors were changed during this diagnostic pass.

## 1.1.2 local direction-correction candidate · 2026-10-24

- User-observed red-only probe: `44 -> 39 -> 44`; user reported white became redder. Blue-only probe: `50 -> 45 -> 50`, repeated once; user reported white became slightly yellower. Every probe restored and read back the original channel value.
- These subjective, local observations motivate a per-display candidate profile, not a universal HKC firmware claim or a colorimetric calibration. Bidirectional behavior and the combined warm/cool adjustment still require user confirmation.
- The candidate applies a signed, clamped five-percent-of-maximum shift to red and blue, keeping green unchanged. At saved original `[44,44,50]`, warm target is `[39,44,45]`, cool target `[49,44,55]`, neutral restores `[44,44,50]`.
- The profile is stored only under this display's local UUID preference key; no physical display ID is hardcoded in source. Unknown or other display IDs do not automatically receive it.
- 18 tests pass, including candidate direction, unchanged green, clamping, neutral/nonfinite recovery and per-display preference isolation. Release build and ad-hoc signature verification passed. No automatic startup color writes were added.
- Local candidate only; not published to GitHub pending user verification.

## 1.1.3 local blue-only candidate · 2026-10-24

- User rejected 1.1.2 combined red/blue adjustment: cool still looked slightly red and warm very red. The inferred inverse-red compensation is not validated and is removed, rather than generalized to other displays.
- Replaced the local profile with `blueOnlyNormal`: red and green remain at saved original values for every slider position, blue alone shifts at most five percent of its maximum. At `[44,44,50]`, warm is `[44,44,45]`, cool `[44,44,55]`, neutral is original. This is limited blue/yellow tint control, not precise color-temperature correction.
- Old `inverseRedNormalBlue` profile strings are rejected by the enum decoder. Core tests verify unchanged red/green, blue clamping, neutral restoration, UUID isolation and rejection of the retired profile. All 18 tests pass; release build and staged signature verification pass.
- The previous tint was restored to saved `[44,44,50]` and read back before starting the new local candidate. User physical validation is still pending; not uploaded to GitHub.

## 1.1.4 release · 2026-10-24

- User subsequently confirmed that 1.1.3 blue-only direction/effect was correct, then requested more visible cold/warm endpoints and publication. That is subjective visual confirmation, not measured CCT.
- Doubled blue-only endpoint offset from 5% to 10% of the channel maximum. Neutral preserves original and half travel gives the old endpoint amount; red and green remain at the saved original. Given original `[44,44,50]`, warm is `[44,44,40]`, cool is `[44,44,60]`. Values clamp to valid device ranges.
- Generic experimental opt-in now also explicitly uses blue-only control, never the retired multi-channel approximation. Existing local direction preferences remain UUID scoped and are not included in the app archive.
- Reused the same target-change reset for explicit and automatic screen selection, clearing experimental opt-in and stale color state on both paths. Added a model-state regression; 19 tests pass after expected range assertions first failed against the old five-percent implementation.
- Preserves the dual-screen popup fix. Includes a read-only `--panel-preview PATH` diagnostic for rendering documentation without changing brightness or color; render captures do not replace physical screen-boundary checks.
- Release archive is ad-hoc signed and verified, not Apple notarized. New ±10 endpoints have not been measured with a colorimeter; ±5 direction was user-confirmed. No automatic startup color writes are introduced.

# Blue-only range extension and release

User confirmed 1.1.3's blue-only direction and requested a more visible effect at the ends plus GitHub publication. Keep the existing slider and validated blue-only approach, doubling the maximum offset from 5% to 10% of the channel maximum. Neutral remains the original color; half travel equals the previously confirmed full-travel offset. Clamp to the monitor's range, never cumulatively add offsets, and retain original red and green.

Publish 1.1.4 with the previously confirmed dual-screen popup fix, safer experimental defaults, Chinese documentation, updated preview, and app archive. A new user's experimental opt-in must also use blue-only control, not the retired multi-channel approximation. Local direction preferences and actual device UUIDs are not shipped. Known original `[44,44,50]` gives blue endpoints 40 and 60; these represent hardware settings, not Kelvin. The old 45/55 effect was user-confirmed; the larger endpoints are not yet physically colorimetrically validated.

Before publication, regression-test channel stability, neutral/half-travel and range limits; ensure automatic display changes reset experimental permission; run all tests and release signing checks; verify GitHub's archive hash and workflow. Keep unrelated workspace changes untouched.

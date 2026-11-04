# Verification — 2026-09-28

Environment: macOS 26.3 (25D2125), Apple silicon, Xcode 26.6 (17F113).
The workspace has no Git metadata, so no commit or PR identity is claimed.

## Fixes under verification

- Idle ordinary typing and key-up avoid expensive host text/caret reads.
- Modified picker keys pass through; stale/non-caret text ranges fail closed.
- Input runtime data and search indexes are reused and loaded off the input path.
- Settings load/persistence and signature inspection move off the UI thread.
- Companion autocomplete is scoped to its focused test field and performs real
  replacement; menu visibility and Test actions follow preferences.
- Legacy system-wide installations are detected; duplicate installs are blocked.
- Ad-hoc signatures are rejected by the production installer. Failed rollback
  preserves the recovery bundle.
- Initial settings, tags, and tones use independent generation checks, so an
  early setting change cannot discard unrelated persisted data. All tone/tag
  writes and index rebuilds gate autocomplete until the newest engine is ready.

## Automated evidence

The final full integration run passed all 121 tests, both Debug application
builds, generated-data reproducibility, and input-method bundle validation.
This includes three added regressions for persisted startup tags/tones and
immediate Enter handling during local/external tone updates. Raw logs are kept
under `Build/Verification`.

| Suite | Passing tests |
|---|---:|
| Models | 6 |
| Emoji data | 7 |
| Search | 11 |
| Tokenization and text commit | 26 |
| Settings persistence and installation | 19 |
| Picker models and input pass-through | 28 |
| Desktop integration | 18 |
| Emoji generator | 6 |

The optimized search benchmark ran 1,500 synthetic warm queries against 1,914
entries. Dataset load was 19.01 ms; index construction 3.01 ms; query median
1.26 ms, p95 2.49 ms, maximum 2.79 ms. These measure search, not end-to-end
InputMethodKit IPC or visible UI frame latency. Machine-readable output is in
`Build/Verification/benchmark.json`.

Release packaging initially exposed Xcode choosing only the host architecture.
The build script now uses the generic macOS destination for Release; both
executables have been verified as `arm64 x86_64`, and both packaging scripts
reject missing architectures. The unsigned preview DMG passed `hdiutil verify`.
Packaging stages output before moving it into its final location, so a failure
does not leave an apparently complete artifact.

## Local update

The final deliverable is a 0.2.0 development update package containing the
companion and system-wide input method. Its app payloads use the local Apple
Development identity; the installer itself is unsigned and not notarized.
The Release build and package creation passed. The expanded package's two app
payloads passed `codesign --verify --deep --strict` and `lipo -verify_arch arm64
x86_64`; its embedded and system-wide input-method executables match byte for
byte. The final package is
`Build/DevelopmentUpdate/Colon-0.2.0-development-update.pkg` with SHA-256
`5aabb39202f562604a66429d1fca2ac7af5be1d58a07e6a7645947383299501d`.
Machine-readable results are in `Build/Verification/package-summary.json`.

Complete the macOS administrator Installer flow, then log out/in. Open Colon
and use the local fixture at `Tests/Fixtures/compatibility.html` in Chrome to
exercise ordinary typing, replacements, shortcuts, caret movement, tones,
disabling Colon, and protected input.

## Limits

Computer Use returned “Computer Use permissions are not granted”, so this session
cannot verify typing in live Chrome or interact with the settings window. Unit,
integration, and build checks are not a substitute for that manual acceptance.

The running installed input method is an older, administrator-owned bundle at
`/Library/Input Methods/ColonInputMethod.app`. Preparing a package does not update
that process. Installing the development update and logging out/in are required
before testing the new server.

A local Apple Development signing identity is available; a Developer ID identity
and notarization profile were not provided. Public notarized V1 distribution and
the eight-app/macOS 27/Intel/display acceptance matrix are not certified here.

# Colon Compatibility Matrix

This checklist is versioned with the codebase. A release candidate cannot pass
Step 17 while any required cell is untested or has a known text-loss,
text-corruption, secure-input, focus, range, or composition defect.

## Test Environments

| Environment | Architecture | Status | Notes |
|---|---|---|---|
| macOS 26 current stable | Apple silicon | Not run | Required |
| macOS 26 current stable | Intel | Not run | Required when hardware/CI is available |
| macOS 27 current beta/stable | Apple silicon | Not run | Required when available |

## Application Matrix

For each app, test plain text, rich text, web/Electron editors where applicable,
multiple windows, rapid app switching, mouse commit, Enter commit, closing-colon
commit, skin tones, undo/redo, no results, Escape, secure fields, and per-app
disablement.

| Application | Plain | Rich/Web | Multiwindow | Secure | Undo | Status |
|---|---|---|---|---|---|---|
| Messages | Not run | Not run | Not run | N/A | Not run | Pending |
| Notes | Not run | Not run | Not run | N/A | Not run | Pending |
| Mail | Not run | Not run | Not run | N/A | Not run | Pending |
| Safari | Not run | Not run | Not run | Not run | Not run | Pending |
| Google Chrome | Not run | Not run | Not run | Not run | Not run | Pending |
| Slack | Not run | Not run | Not run | Not run | Not run | Pending |
| Discord | Not run | Not run | Not run | Not run | Not run | Pending |
| Notion | Not run | Not run | Not run | Not run | Not run | Pending |

## Display Matrix

| Scenario | Status | Notes |
|---|---|---|
| Single display, caret near every edge | Not run | Panel must remain visible |
| Multiple displays with mixed scaling | Not run | Panel must use caret display |
| Full-screen host application | Not run | Panel must not activate itself |
| Rapid Space/app/window switching | Not run | No stale panel or commit |

## Slack and Discord Native Emoji UI

The required test determines whether Colon and the host emoji UI appear
simultaneously. Colon must not simulate keystrokes or use app-specific private
APIs. If overlap is disruptive and cannot be solved through the centralized
InputMethodKit adapter, the release decision must be documented rather than
hidden behind scattered app-specific behavior.

## Performance Gates

- Bundled dataset cold load test passes.
- Warm deterministic query latency test passes.
- Candidate panel interaction remains visually immediate under rapid typing.
- Idle input method and companion CPU are measured with Instruments/Activity
  Monitor and recorded here before release.
- Memory is measured after activation, 100 searches, app switching, and idle.

## Release-Candidate Record

Record tested app versions, macOS builds, hardware, failures, and linked
regression tests here when the manual matrix is executed.

## September 2026 development verification

See [verification record](verification-2026-09-28.md) for the 0.2.0 automated
results and explicit live-test limits. Use `Tests/Fixtures/compatibility.html` in
Chrome/Safari for synthetic plain, multiline, rich, and password-field checks;
it has no scripts, forms, persistent storage, or network resources. Do not mark
an app row passed based solely on core/model tests.

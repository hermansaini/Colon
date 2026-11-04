# Verification — Colon 0.2.1, 2026-10-22

This update addresses tone navigation, correcting a shortcode, and caret-relative
picker placement. The installed companion and system-wide input method both
reported 0.1.0 at the start of this session; source changes do not update those
running copies.

## Changes

- Repeated unchanged text/caret refreshes preserve the active tone selection.
  Enter and a closing colon insert the selected tone and remember it.
- The companion test field uses a native field-editor delegate to intercept Tab
  before focus traversal. Only unmodified picker commands from that field are
  handled; Shift-Tab, shortcuts, and marked-text composition pass through.
- Text, selection, and caret coordinates arrive as one snapshot, avoiding a hide
  between independent text/selection updates.
- An already-open picker stays visible when the same shortcode is edited back
  to a bare colon or an unmatched query. Previous rows are disabled and a prompt
  explains the state. Enter/Tab pass through, stale mouse callbacks cannot commit,
  and matching input re-enables results. Escape still suppresses the token.
- Standard rows are 320 × 36 points (six visible rows: 320 × 216); compact rows
  are 280 × 32. Rows show an emoji and shortcode on one line.
- Both picker panels prefer above the caret, flip below near the top edge, and
  clamp within the caret's display. The companion no longer uses manual screen
  anchor sliders. The input method uses IMK's current-selection line rectangle,
  with a validated first-character-rectangle fallback. Zero/invalid/off-screen
  geometry produces no popup or invisible keyboard commit.

## Automated checks

The full CI run passed 130 tests: Models 6, EmojiData 7, Search 11, Tokenization 26,
SettingsCore 19, PickerModels 34, desktop integration 21, and generator 6. Both
Debug apps built, bundle metadata/license validation passed, and generated data
matched the pinned inputs. The final desktop run also covers the native field
bridge after its scroll-observer addition.

Both Release app payloads passed strict signature verification, contain arm64
and x86_64 binaries, and report version 0.2.1/build 3. The embedded and system-wide
input-method executables match byte for byte. Final installer SHA-256:
`44f982a24840c871bc821d049d5853eea1b731d357a367115b55edc02321a836`.

New coverage includes native Tab command routing, repeated tone cycling and
insertion, closing-colon tone preservation, typo/delete/retype transitions,
noncommittable correction rows, Escape suppression, unavailable caret pass-through,
above/below positioning, invalid rectangles, and a secondary display at negative
coordinates. Logs and package verification are under `Build/Verification/2026-10-22`.

## Install and live checks

Use `Build/DevelopmentUpdate/Colon-0.2.1-development-update.pkg`. It updates
`/Applications/Colon.app` and `/Library/Input Methods/ColonInputMethod.app` in
place. The payload apps are Apple Development signed; the installer is unsigned
and not notarized. Complete the administrator Installer flow, then log out/in
before checking the new input-method process.

1. In Colon's test field, type `:wave`, press Tab several times, then Enter. Repeat
   with a closing colon. Both should insert the currently highlighted tone.
2. In Chrome, open `Tests/Fixtures/compatibility.html` and repeat the same sequence.
3. Type `:fire`, append `zzzzzz`, delete back to `:`, then type `wave`. The popup
   should stay through correction, with old rows disabled until matching results
   return. Escape should still dismiss it.
4. Verify the popup follows the caret, prefers above, and flips below near the
   display's top edge. Check a secondary display and moving the settings window.
5. Confirm Shift-Tab, normal typing, selection, Undo, and password input stay native.

Computer Use again returned “Computer Use permissions are not granted”. No live
Chrome/settings acceptance or installed-process replacement is claimed. A native
field-delegate regression test is not a substitute for an end-to-end UI test.

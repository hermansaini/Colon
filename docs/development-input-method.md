# Development Input Method

Before installing, add your Apple Account in Xcode → Settings → Accounts and
create an **Apple Development** certificate. Current macOS releases discover an
ad-hoc-signed input method but do not allow it to remain enabled. The installer
fails before replacing an existing bundle when no Apple-issued signing identity
is available. Set `COLON_DEVELOPMENT_SIGNING_IDENTITY` to choose a specific
identity when more than one is installed.

1. Run `./Scripts/build-apps.sh`.
2. Run `./Scripts/install-development-input-method.sh`. The script copies the
   bundle, applies an Apple development signature to the complete installed
   bundle, verifies that signature, and registers the installed URL with Text
   Input Services.
3. Open System Settings → Keyboard → Text Input → Edit.
4. Add **Colon**, then select it from the input menu.
5. Type a paragraph in Notes and Messages to confirm ordinary input remains
   unchanged. TextEdit is intentionally outside the V1 allowlist.

Colon does not request Accessibility permission and does not install a global
event tap. Use Console with subsystem
`org.colonproject.inputmethod.Colon` to inspect privacy-safe lifecycle codes.

## Step 12 candidate smoke test

Complete this sequence in Notes, then Messages:

1. Type `:f` and confirm the six-row candidate panel appears at the caret after
   the first query letter.
2. Continue to `:fire` and confirm the results narrow while all typed text stays
   in the document.
3. Type an unmatched query such as `:zzzzzz` and confirm the last rows remain visible but disabled.
4. Backspace to a matching query and confirm candidates return.
5. Press Escape and confirm the panel hides without changing the token; continue
   typing and confirm that token remains suppressed until a boundary.
6. Move between two windows and then between Notes and Messages;
   confirm old panels close and no stale selection appears.
7. While the panel is visible, continue typing and confirm the host application
   remains active and receives focus, selection, and editing commands.

## Step 13 commit smoke test

Step 13 replaces shortcodes through the host's native input-client API. Complete
this sequence in Notes and Messages:

1. Type `start :fire end`, place the caret immediately after `:fire`, and press
   Enter. Confirm the result is `start 🔥 end` with no shortcode characters.
2. Undo once with Command-Z and confirm the host restores `:fire` as one native
   edit; redo once and confirm the emoji returns.
3. Type `:wave:` and confirm the intercepted closing colon replaces both colons
   and the query without inserting a duplicate colon.
4. Type `:f`, click a non-first result, and confirm that exact result commits
   while the host remains the active application.
5. Select an emoji with skin-tone variants, press Tab repeatedly to cycle the
   tone overlay, then press Enter. Confirm the selected variant commits.
6. Repeat the tone flow by clicking a variant. Start a new query for the same
   emoji and confirm the last successfully committed variant is remembered.
7. Type a query for an emoji without skin-tone variants and press Tab. Confirm
   Tab passes through to the host and does not commit the emoji.
8. Show candidates, switch windows or applications, then click where the old
   panel was. Confirm no stale callback edits the new client.

If pre-commit session, query, selection, or UTF-16 range validation fails, Colon
hides its panels and leaves the shortcode unchanged. Failed commits do not write
skin-tone preferences.

## Step 14 compatibility and secure-input smoke test

Colon allows only Messages, Notes, Mail, Safari, Google Chrome, Slack, Discord,
and Notion. It checks the IMK client identity against the frontmost application,
applies global and per-app settings, and fails closed while macOS secure event
input is enabled.

1. Confirm `:fire` presents and commits in each installed supported app.
2. Disable Messages in Colon settings while its panel is visible. Confirm the
   panel closes immediately and later Messages input passes through unchanged.
3. Disable Colon globally and confirm active UI closes in every app; re-enable it
   and confirm the selected app works again.
4. Type `:fire` in TextEdit or another unsupported app. Confirm no Colon panel
   appears and ordinary typing is unaffected.
5. In Safari and Chrome, focus a password field and type colon-prefixed text.
   Confirm no panel appears and no replacement occurs.
6. Repeat the password-field check in a system authentication dialog and an
   installed password manager.
7. Show a panel in one supported app, then rapidly switch to another app/window.
   Confirm the old panel closes and cannot commit into the new client.

Secure-input handling uses the public `IsSecureEventInputEnabled` API on the main
thread. Missing security state, missing client identity, client/frontmost-app
mismatch, unknown apps, and unavailable settings all suppress token processing.

## Step 15 companion installation smoke test

Release builds embed `ColonInputMethod.app` under the companion app's
`Contents/Library/Input Methods` directory. The companion validates the source
signature and bundle identifier before any copy, stages upgrades in the user
Input Methods directory, validates the installed copy, and rolls back a failed
replacement.

1. Start from an account without Colon in `~/Library/Input Methods` and launch
   the signed companion app.
2. Click **Install Input Method** and confirm the status advances to discovered,
   enabled, selected, or an explicit logout/login instruction.
3. If needed, log out and back in, then open System Settings → Keyboard → Text
   Input → Edit and add Colon.
4. Click **Enable & Select**. If macOS rejects programmatic enablement, follow
   the displayed System Settings guidance, then click **Refresh**.
5. Confirm the status reads **Installed, enabled, and selected**, then commit
   `:fire` in Messages as the live readiness test.
6. Install a newer signed build and confirm it replaces the older input-method
   bundle without losing settings.
7. Click **Uninstall**, confirm the destructive prompt, and verify only the
   validated user-scoped Colon bundle is removed.

Unsigned CI/debug artifacts intentionally fail the production signature check;
use `./Scripts/install-development-input-method.sh` for local Apple-signed
testing.

## Step 16 utility smoke test

1. Toggle **Launch companion app at login** and confirm the displayed
   `SMAppService.mainApp` status changes. If approval is required, use System
   Settings → General → Login Items; Colon never silently re-enables itself.
2. Hide and show the menu bar item. Confirm hiding it does not disable the input
   method and settings remain available by launching Colon normally.
3. Verify the menu provides Open Settings, Enable/Disable, Test Colon, and Quit
   Companion App actions.
4. Click **Export Redacted Diagnostics** and inspect the JSON file. It may contain
   versions, readiness booleans, supported-app identities, architecture, and
   allowlisted error codes; it must not contain queries or surrounding text.

Diagnostic events are local, bounded to the newest 200 entries per companion
process, and exported only after explicit user action.

After rebuilding, reinstall the bundle. Log out and back in if macOS does not
refresh the registered input source immediately.

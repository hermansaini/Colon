# Privacy

Colon processes emoji queries locally. It has no accounts, analytics, advertising,
cloud sync, automatic updater, or runtime network requests.

The InputMethodKit adapter reads only bounded text immediately before the caret
in supported, enabled applications. Secure-input state, client identity, and text
ranges are checked before processing; unavailable context disables autocomplete
for that event. Queries and surrounding text are not written to storage or logs.

Settings, custom tags, and per-emoji skin tones are stored as versioned JSON in
`~/Library/Application Support/Colon/`. Damaged documents are preserved as `.bak`
files before recovery. Removing an input method preserves preferences; users may
remove this directory separately to erase Colon's local data.

Diagnostic exports are explicitly user-initiated. They contain allowlisted
operational metadata (app/OS versions, supported app identities, installation
status, and error codes), not typed text, queries, or clipboard contents. Inspect
an export before sharing it. System lifecycle logs likewise use fixed event codes.

Downloading releases and optional notarization during release creation use the
network; ordinary typing, emoji search, and settings do not.

# Reusable core and desktop boundary

ColonModels defines value types and persisted snapshots. ColonEmojiData validates
and loads the bundled Unicode dataset. ColonTokenization works in UTF-16 ranges
and reads bounded context through MinimalTextClient/TextCommitClient adapters.
ColonSearch returns deterministic ranked candidates. ColonPickerModels is a pure
state machine plus platform-neutral geometry and compatibility rules.
ColonSettingsCore owns local JSON storage and desktop installation services.

AppKit, InputMethodKit, Security, Carbon Text Input Services, and ServiceManagement
belong to the desktop app/adapters. Core search/tokenization do not request input
permissions, access host applications, or read a clipboard. Future keyboard or
Messages extensions should supply bounded text-context and commit adapters,
settings storage appropriate to their container, and their own panel UI. An iOS
host cannot assume macOS absolute-range replacement or caret rectangles; its
adapter must explicitly report unavailable capabilities and fail safely.

The existing package manifests target macOS 26. Cross-platform support is an
architectural boundary, not an iOS compatibility claim. In particular,
DistributedNotificationCenter in ColonSettingsCore requires a platform-specific
notification adapter before an iOS target is enabled. An iOS keyboard and Messages
extension remain future work; no extension or shared app group ships in this
preview.

`swift test` at the repository root builds the companion UI as a test module and
runs desktop regression tests with isolated storage. It does not install/select
an input source. `Scripts/ci.sh` additionally tests all core packages, validates
reproducible emoji data, and builds both application targets.

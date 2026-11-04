# Security policy

Text integrity and privacy are release-critical. Report security issues privately
to the repository maintainer through the hosting service's private vulnerability
reporting facility, when enabled. Do not post passwords, messages, or real input
context in public issues. Include the Colon/macOS/app version and a reproduction
using synthetic text.

Colon uses InputMethodKit rather than Accessibility permission, global event
taps, clipboard insertion, or simulated backspaces. Client identity, secure input,
selection, and UTF-16 replacement ranges must be validated before a native commit.
Unknown/unsupported contexts must remain ordinary passthrough typing.

Release artifacts must be Developer ID signed and notarized. Development and
unsigned previews are not equivalent to verified distribution builds. See
`docs/release.md` for verification and `docs/compatibility-matrix.md` for outstanding
manual coverage. Build and release credentials must never be committed.

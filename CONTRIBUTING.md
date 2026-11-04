# Contributing

Bug reports, documentation improvements, and focused pull requests are welcome.
For bugs, include macOS and Colon versions, the affected application, expected
behavior, and steps using synthetic text. Never include private typed content.
Discuss substantial changes in an issue before implementing them.

## Development

1. Install Xcode 26 or later on macOS 26 or later and accept its license.
2. Download or clone the repository and open `Colon.xcworkspace`.
3. Run `./Scripts/ci.sh` from the repository root before submitting changes.
4. For live input-method testing, follow [development installation](docs/development-input-method.md).

Preserve text integrity, secure-field passthrough, deterministic emoji data, and
local-only operation. Add regression coverage for behavior changes. UI and host
integration changes also need relevant manual checks from the
[compatibility matrix](docs/compatibility-matrix.md).

Keep pull requests focused; describe the problem, resulting behavior, and checks
performed. Do not commit credentials, signing material, build products, or user
content. Contributions are provided under the repository's MIT license.

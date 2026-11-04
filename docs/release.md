# Release builds

Colon is currently a preview. Do not describe an unsigned or development-signed
build as notarized, or publish 1.0 until the compatibility checklist is complete.

## Local universal preview

Run `./Scripts/ci.sh`, then `./Scripts/package-release.sh --unsigned`.
The latter creates an optimized arm64/x86_64 DMG and SHA-256 checksum under
`Build/Releases`. This preview is for local evaluation and does not pass the
production installer signature policy. It is not a public distribution artifact.
Use a unique `COLON_RELEASE_OUTPUT` directory for each build; existing artifacts
are never overwritten. `DERIVED_DATA_PATH` can isolate builds from old/root-owned
Xcode output. Never run builds using sudo.

## Signed and notarized distribution

Prerequisites: an installed **Developer ID Application** signing identity and a
`notarytool` Keychain profile. An Apple Development identity is insufficient for
public distribution. Keep private keys, profile credentials, and certificates out
of the repository and pull-request CI.

```sh
COLON_RELEASE_SIGNING_IDENTITY='Developer ID Application: …' \
COLON_NOTARY_PROFILE='colon-release' \
./Scripts/package-release.sh --notarize
```

The script builds Release/Universal 2, verifies bundle metadata and architecture,
signs the nested input method before the companion, verifies signatures, submits
to Apple, staples tickets, assesses the app, packages a DMG, notarizes/staples the
DMG, and computes the final checksum. Submission requires network access. No
GitHub release is created automatically. This follows Apple's
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Before publishing, record evidence in `docs/compatibility-matrix.md`: all eight
apps, supported OS/hardware, protected input, text integrity, focus switching,
installer upgrade/uninstall, and idle/interactive performance. Test the downloaded
DMG on a clean account. Attach the artifact, checksum, versioned release notes,
known limitations, and privacy/uninstall instructions to a reviewed release.

## Existing system-wide development installations

Older development packages installed Colon into `/Library/Input Methods`.
Do not also install the same input source in `~/Library/Input Methods`. Update the
system-wide bundle with an administrator installer, or select another keyboard,
remove the old bundle with administrator privileges, log out/in, then use the
user-scoped companion installer. A running input-method process retains its old
code until restarted; replacing files alone does not prove the fix is active.

To prepare a local upgrade package for an existing system-wide development
installation, run `./Scripts/package-development-update.sh`. It uses an installed
Apple Development identity, builds optimized Universal 2 apps, and creates a
package under `Build/DevelopmentUpdate`. The package updates `/Applications/Colon.app`
and `/Library/Input Methods/ColonInputMethod.app`; it does not run automatically.
The app payloads are development-signed, while the installer package itself is
unsigned and not notarized. Use it only on the development Mac. Complete the
administrator Installer flow, then log out/in before testing the new server.

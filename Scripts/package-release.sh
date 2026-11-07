#!/bin/sh
# Build a universal preview, or sign/notarize a release with explicit credentials.
set -eu
root_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:---unsigned}
case "$mode" in --unsigned|--notarize) ;; *) echo 'Usage: package-release.sh [--unsigned|--notarize]' >&2; exit 2 ;; esac
if [ "$mode" = --notarize ]; then
    : "${COLON_RELEASE_SIGNING_IDENTITY:?Set a Developer ID Application identity}"
    : "${COLON_NOTARY_PROFILE:?Set a notarytool keychain profile}"
fi
export DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${root_directory}/Build/ReleaseDerivedData}"
export CONFIGURATION=Release
"${root_directory}/Scripts/build-apps.sh"
"${root_directory}/Scripts/validate-input-method.sh"
output_directory="${COLON_RELEASE_OUTPUT:-${root_directory}/Build/Releases}"
mkdir -p "$output_directory"
staging_directory=$(mktemp -d "${output_directory}/.staging.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT HUP INT TERM
payload_directory="${staging_directory}/payload"
mkdir -p "$payload_directory"
app="${payload_directory}/Colon.app"
ditto "${DERIVED_DATA_PATH}/Build/Products/Release/Colon.app" "$app"
input_method="${app}/Contents/Library/Input Methods/ColonInputMethod.app"
for executable in "${app}/Contents/MacOS/Colon" "${input_method}/Contents/MacOS/ColonInputMethod"; do
    if ! lipo "$executable" -verify_arch arm64 x86_64; then
        echo "Release executable must contain arm64 and x86_64: $executable" >&2
        exit 1
    fi
done
version=$(plutil -extract CFBundleShortVersionString raw -o - "${app}/Contents/Info.plist")
suffix=unsigned-preview
if [ "$mode" = --notarize ]; then suffix=macOS; fi
dmg="${output_directory}/Colon-${version}-${suffix}.dmg"
if [ -e "$dmg" ]; then
    echo "Output already exists: $dmg. Choose COLON_RELEASE_OUTPUT or move it first." >&2
    exit 1
fi
if [ "$mode" = --notarize ]; then
    sign_bundle() {
        bundle=$1
        codesign --force --options runtime --timestamp --sign "$COLON_RELEASE_SIGNING_IDENTITY" "$bundle"
        codesign --verify --deep --strict "$bundle"
        codesign -dvv "$bundle" 2>&1 | grep -q '^Authority=Developer ID Application:'
    }
    # The companion seals this embedded input method as a resource. Finish
    # stapling the nested ticket before signing the enclosing companion.
    sign_bundle "$input_method"
    ditto -c -k --keepParent "$input_method" "${staging_directory}/input-method.zip"
    xcrun notarytool submit "${staging_directory}/input-method.zip" --keychain-profile "$COLON_NOTARY_PROFILE" --wait
    xcrun stapler staple "$input_method"
    xcrun stapler validate "$input_method"
    sign_bundle "$app"
    ditto -c -k --keepParent "$app" "${staging_directory}/submission.zip"
    xcrun notarytool submit "${staging_directory}/submission.zip" --keychain-profile "$COLON_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
fi
ln -s /Applications "${payload_directory}/Applications"
# Work in staging so a failed notarization leaves no apparently finished artifact.
temporary_dmg="${staging_directory}/Colon.dmg"
hdiutil create -volname Colon -srcfolder "$payload_directory" -format UDZO "$temporary_dmg"
if [ "$mode" = --notarize ]; then
    codesign --timestamp --sign "$COLON_RELEASE_SIGNING_IDENTITY" "$temporary_dmg"
    xcrun notarytool submit "$temporary_dmg" --keychain-profile "$COLON_NOTARY_PROFILE" --wait
    xcrun stapler staple "$temporary_dmg"
    xcrun stapler validate "$temporary_dmg"
fi
checksum=$(shasum -a 256 "$temporary_dmg" | awk '{print $1}')
printf '%s  %s\n' "$checksum" "$(basename "$dmg")" > "${staging_directory}/checksum.sha256"
mv "$temporary_dmg" "$dmg"
mv "${staging_directory}/checksum.sha256" "${dmg}.sha256"
printf 'Created %s\n' "$dmg"

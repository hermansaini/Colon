#!/bin/sh
set -eu
root_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data_path="${DERIVED_DATA_PATH:-${root_directory}/DerivedData}"
configuration="${CONFIGURATION:-Debug}"
source_bundle="${derived_data_path}/Build/Products/${configuration}/ColonInputMethod.app"
input_methods_directory="${HOME}/Library/Input Methods"
destination_bundle="${input_methods_directory}/ColonInputMethod.app"
signing_identity="${COLON_DEVELOPMENT_SIGNING_IDENTITY:-}"
if [ ! -d "$source_bundle" ]; then
    echo 'Build the ColonInputMethod scheme before installing.' >&2; exit 1
fi
if [ -d '/Library/Input Methods/ColonInputMethod.app' ]; then
    echo 'A system-wide Colon installation already exists in /Library/Input Methods.' >&2
    echo 'Update that installation with its administrator installer, or remove it after selecting another keyboard.' >&2
    echo 'Refusing to create a second input source with the same identifier.' >&2
    exit 1
fi
if [ -z "$signing_identity" ]; then
    signing_identity=$(security find-identity -v -p codesigning |
        awk '/"(Apple Development|Mac Development|Developer ID Application):/ { print $2; exit }')
fi
if [ -z "$signing_identity" ]; then
    echo 'Create an Apple Development certificate in Xcode Settings > Accounts first.' >&2; exit 1
fi
mkdir -p "$input_methods_directory"
staging_directory=$(mktemp -d "${input_methods_directory}/.colon-install.XXXXXX")
staged_bundle="${staging_directory}/ColonInputMethod.app"
backup_bundle="${staging_directory}/previous.app"
cleanup() {
    # Restore the previous bundle if replacement failed after moving it aside.
    if [ -d "$backup_bundle" ] && [ ! -e "$destination_bundle" ]; then
        mv "$backup_bundle" "$destination_bundle"
    fi
    rm -rf "$staging_directory"
}
trap cleanup EXIT HUP INT TERM
ditto "$source_bundle" "$staged_bundle"
codesign --force --options runtime --timestamp=none --sign "$signing_identity" \
    --identifier org.colonproject.inputmethod.Colon "$staged_bundle"
codesign --verify --deep --strict --verbose=2 "$staged_bundle"
if [ -e "$destination_bundle" ]; then
    mv "$destination_bundle" "$backup_bundle"
fi
mv "$staged_bundle" "$destination_bundle"
if ! xcrun swift "${root_directory}/Scripts/register-input-source.swift" "$destination_bundle"; then
    rm -rf "$destination_bundle"
    exit 1
fi
printf 'Installed %s\n' "$destination_bundle"
echo 'Log out and back in to load the updated input-method process.'

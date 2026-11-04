#!/bin/sh
# Local Apple Development-signed upgrade for legacy /Library/Input Methods installs.
# Produces a package; never invokes Installer or changes the selected keyboard.
set -eu
root_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${root_directory}/Build/ReleaseDerivedData}"
export CONFIGURATION=Release
identity="${COLON_DEVELOPMENT_SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity=$(security find-identity -v -p codesigning |
        awk '/"(Apple Development|Mac Development):/ { print $2; exit }')
fi
if [ -z "$identity" ]; then
    echo 'An Apple Development signing identity is required.' >&2; exit 1
fi
"${root_directory}/Scripts/build-apps.sh"
"${root_directory}/Scripts/validate-input-method.sh"
output_directory="${COLON_RELEASE_OUTPUT:-${root_directory}/Build/DevelopmentUpdate}"
mkdir -p "$output_directory"
staging_directory=$(mktemp -d "${output_directory}/.staging.XXXXXX")
trap 'rm -rf "$staging_directory"' EXIT HUP INT TERM
package_root="${staging_directory}/root"
mkdir -p "${package_root}/Applications" "${package_root}/Library/Input Methods"
app="${package_root}/Applications/Colon.app"
ditto "${DERIVED_DATA_PATH}/Build/Products/Release/Colon.app" "$app"
embedded="${app}/Contents/Library/Input Methods/ColonInputMethod.app"
for executable in "${app}/Contents/MacOS/Colon" "${embedded}/Contents/MacOS/ColonInputMethod"; do
    if ! lipo "$executable" -verify_arch arm64 x86_64; then
        echo "Release executable must contain arm64 and x86_64: $executable" >&2
        exit 1
    fi
done
codesign --force --options runtime --timestamp=none --sign "$identity" "$embedded"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
ditto "$embedded" "${package_root}/Library/Input Methods/ColonInputMethod.app"
pkgbuild --analyze --root "$package_root" "${staging_directory}/components.plist"
/usr/bin/python3 - "${staging_directory}/components.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
with open(p, 'rb') as f:
    components = plistlib.load(f)
def configure(component):
    component['BundleIsRelocatable'] = False
    component['BundleIsVersionChecked'] = False
    component['BundleHasStrictIdentifier'] = True
    component['BundleOverwriteAction'] = 'upgrade'
    for child in component.get('ChildBundles', []):
        configure(child)
for component in components:
    configure(component)
with open(p, 'wb') as f:
    plistlib.dump(components, f)
PY
version=$(plutil -extract CFBundleShortVersionString raw -o - "${app}/Contents/Info.plist")
package="${output_directory}/Colon-${version}-development-update.pkg"
if [ -e "$package" ]; then
    echo "Output exists: $package. Choose a new COLON_RELEASE_OUTPUT directory." >&2; exit 1
fi
temporary_package="${staging_directory}/Colon.pkg"
pkgbuild --root "$package_root" --install-location / \
    --component-plist "${staging_directory}/components.plist" \
    --identifier org.colonproject.development.update --version "$version" "$temporary_package"
checksum=$(shasum -a 256 "$temporary_package" | awk '{print $1}')
printf '%s  %s\n' "$checksum" "$(basename "$package")" > "${staging_directory}/checksum.sha256"
mv "$temporary_package" "$package"
mv "${staging_directory}/checksum.sha256" "${package}.sha256"
printf 'Created local development update: %s\n' "$package"
echo 'This package is not notarized. Install only on your development Mac, then log out/in.'
echo 'It updates /Applications/Colon.app and /Library/Input Methods/ColonInputMethod.app.'

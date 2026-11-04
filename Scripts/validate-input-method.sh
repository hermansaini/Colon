#!/bin/sh

set -eu

root_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data_path="${DERIVED_DATA_PATH:-${root_directory}/DerivedData}"
configuration="${CONFIGURATION:-Debug}"
source_plist="${root_directory}/Apps/ColonInputMethod/Resources/Info.plist"
built_bundle="${derived_data_path}/Build/Products/${configuration}/ColonInputMethod.app"
built_plist="${built_bundle}/Contents/Info.plist"
built_executable="${built_bundle}/Contents/MacOS/ColonInputMethod"
built_icon="${built_bundle}/Contents/Resources/ColonInputMethodIcon.tiff"
embedded_bundle="${derived_data_path}/Build/Products/${configuration}/Colon.app/Contents/Library/Input Methods/ColonInputMethod.app"
embedded_plist="${embedded_bundle}/Contents/Info.plist"
embedded_executable="${embedded_bundle}/Contents/MacOS/ColonInputMethod"

plutil -lint "${source_plist}"
test -f "${built_plist}"
test -x "${built_executable}"

assert_plist_value() {
    key=$1
    expected=$2
    actual=$(plutil -extract "${key}" raw -o - "${built_plist}")
    if [ "${actual}" != "${expected}" ]; then
        echo "Unexpected ${key}: ${actual}" >&2
        exit 1
    fi
}

assert_plist_value CFBundlePackageType APPL
assert_plist_value InputMethodServerControllerClass ColonInputController
assert_plist_value TISInputSourceCategory TISCategoryInputMethod
assert_plist_value TISInputSourceID org.colonproject.inputmethod.Colon
assert_plist_value TISIntendedLanguage en
assert_plist_value tsInputMethodIconFileKey ColonInputMethodIcon.tiff

test -f "${built_icon}"
for license in Colon-MIT.txt Unicode.txt CLDR.txt gemoji-MIT.txt THIRD_PARTY_NOTICES.md
do
    test -s "${built_bundle}/Contents/Resources/Licenses/${license}"
    test -s "${embedded_bundle}/Contents/Resources/Licenses/${license}"
done
icon_width=$(sips -g pixelWidth "${built_icon}" | awk '/pixelWidth/ { print $2 }')
icon_height=$(sips -g pixelHeight "${built_icon}" | awk '/pixelHeight/ { print $2 }')
if [ "${icon_width}" != "32" ] || [ "${icon_height}" != "32" ]; then
    echo "Input method icon must be a 32x32 Retina TIFF." >&2
    exit 1
fi

if ! file "${built_executable}" | grep -q "Mach-O"; then
    echo "Input method executable is not a Mach-O executable." >&2
    exit 1
fi

test -f "${embedded_plist}"
test -x "${embedded_executable}"
embedded_identifier=$(plutil -extract CFBundleIdentifier raw -o - "${embedded_plist}")
if [ "${embedded_identifier}" != "org.colonproject.inputmethod.Colon" ]; then
    echo "Unexpected embedded input method identifier: ${embedded_identifier}" >&2
    exit 1
fi

if rg -q "AXIsProcessTrusted|CGEventTapCreate|CGEventTapCreateForPSN" \
    "${root_directory}/Apps/ColonInputMethod"; then
    echo "Input method must not use Accessibility trust or global event taps." >&2
    exit 1
fi

echo "Input method bundle and companion embedding metadata valid."

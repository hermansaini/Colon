#!/bin/sh

set -eu

root_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data_path="${DERIVED_DATA_PATH:-${root_directory}/DerivedData}"
configuration="${CONFIGURATION:-Debug}"
destination="platform=macOS"
if [ "$configuration" = Release ]; then
    destination="generic/platform=macOS"
fi

for scheme in ColonMacApp ColonInputMethod
do
    echo "==> Building ${scheme}"
    xcodebuild \
        -workspace "${root_directory}/Colon.xcworkspace" \
        -scheme "${scheme}" \
        -configuration "${configuration}" \
        -destination "$destination" \
        -derivedDataPath "${derived_data_path}" \
        CODE_SIGNING_ALLOWED=NO \
        build
done

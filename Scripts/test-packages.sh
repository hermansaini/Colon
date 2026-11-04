#!/bin/sh

set -eu

root_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

for package in \
    ColonModels \
    ColonEmojiData \
    ColonSearch \
    ColonTokenization \
    ColonSettingsCore \
    ColonPickerModels
do
    echo "==> Testing ${package}"
    swift test --package-path "${root_directory}/Packages/${package}"
done

echo "==> Testing desktop integration"
swift test --package-path "${root_directory}"

echo "==> Testing EmojiDataGenerator"
swift test --package-path "${root_directory}/Tools/EmojiDataGenerator"

echo "==> Checking generated emoji data"
swift run \
    --package-path "${root_directory}/Tools/EmojiDataGenerator" \
    EmojiDataGenerator \
    --check \
    --root "${root_directory}"

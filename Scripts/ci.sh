#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

"${script_directory}/test-packages.sh"
"${script_directory}/build-apps.sh"
"${script_directory}/validate-input-method.sh"

#!/usr/bin/env bash
set -e

THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"

"$THIS_ABSPATH/setup.sh"
"$THIS_ABSPATH/test-bare.sh"
"$THIS_ABSPATH/teardown.sh"

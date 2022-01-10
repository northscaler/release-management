#!/usr/bin/env bash
set -ex

THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"
TYPES=${*:-nodejs helm version docker csharp maven gradle gradlekts}

for it in $TYPES; do
  export TEST_DOCKER=
  export NO_USE_LOCAL_NODEJS=1
  export NO_USE_LOCAL_NPM=1
  export NO_USE_LOCAL_FX=1
  export NO_USE_LOCAL_YMLX=1
  export NO_USE_LOCAL_MATCH=1
  "$THIS_ABSPATH/test.sh" "$it"

  # TODO: when offering a Docker image for this project
  #  export TEST_DOCKER=1
  #  "$THIS_ABSPATH/test.sh" "$it"
done

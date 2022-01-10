#!/usr/bin/env bash
set -ex

THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"
TYPES="$1"

if [ -n "$TEST_DOCKER" ]; then
  export LOCAL_PATH="$THIS_ABSPATH/$TYPES/local"
  export REMOTE_PATH="$THIS_ABSPATH/$TYPES/remote"
  export PREFIX="docker run --rm -it -v $LOCAL_PATH:/gitrepo -v $REMOTE_PATH:$REMOTE_PATH -e EMAIL=fake@northscaler.com -e GIT_AUTHOR_NAME=$USER -e GIT_COMMITTER_NAME=$USER northscaler"

  docker build --tag northscaler/release -f "$THIS_ABSPATH/../Dockerfile" "$THIS_ABSPATH/.."
fi

"$THIS_ABSPATH/setup.sh" "$TYPES"
"$THIS_ABSPATH/test-bare.sh" "$TYPES"
"$THIS_ABSPATH/teardown.sh" "$TYPES"

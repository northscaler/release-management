#!/usr/bin/env bash
set -e

THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"
ORIGIN=origin
MAIN=dev

LOCAL_PATH="$THIS_ABSPATH/local"
rm -rf "$LOCAL_PATH"
cp -r "$THIS_ABSPATH/local-src" "$LOCAL_PATH"
git init -b $MAIN "$LOCAL_PATH"

REMOTE_PATH="$THIS_ABSPATH/remote"
rm -rf "$REMOTE_PATH"
mkdir -p "$REMOTE_PATH"
git init --bare "$REMOTE_PATH"

(
  cd "$LOCAL_PATH"
  git add .
  git commit -m 'begin test'
  git remote add $ORIGIN "$REMOTE_PATH"
  git push -u $ORIGIN $MAIN
)

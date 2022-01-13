#!/usr/bin/env bash
set -e

THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"

rm -rf \
  "$THIS_ABSPATH/local" \
  "$THIS_ABSPATH/remote"

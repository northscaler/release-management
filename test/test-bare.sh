#!/usr/bin/env bash
set -ex

TEST_TYPE="$1"
THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"

SCRIPT="${SCRIPT:-release.sh}"
PREFIX="${PREFIX:-$THIS_ABSPATH/..}"

OPTS='--pre-rc --helm-chart-dir release-test-chart'

# TODO: test saddy paths

gitLog='git log --pretty=oneline'
gitLastMsg='git log --pretty="%s"  HEAD^..HEAD'

(
  cd "$THIS_ABSPATH/$TEST_TYPE/local"

  echo 'TEST: 1 pre'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" pre
  $gitLog

  echo 'TEST: 2 rc'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" rc
  $gitLog

  echo 'TEST: 3 rc'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" rc
  $gitLog

  echo 'TEST: 4 minor'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" minor
  $gitLog

  echo 'TEST: 5 rc'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" rc
  $gitLog

  echo 'TEST: 6 patch'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" patch
  $gitLog

  echo 'TEST: 7 rc'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" rc
  $gitLog

  git checkout master

  echo 'TEST: 8 pre'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" pre
  $gitLog

  echo 'TEST: 9 rc'
  $PREFIX/$SCRIPT $OPTS --tech "$TEST_TYPE" rc
  $gitLog
)

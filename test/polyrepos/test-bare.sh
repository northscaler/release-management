#!/usr/bin/env bash
set -e

TEST_TYPE="$1"
THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"

SCRIPT="${SCRIPT:-release.sh}"
PREFIX="${PREFIX:-$THIS_ABSPATH/../..}"

OPTS='--pre-rc --helm-chart-dir release-test-chart --verbose'

# TODO: test assertions & saddy paths

gitLog='git log --pretty=oneline'
gitLastMsg='git log --pretty="%s"  HEAD^..HEAD'

(
  cd "$THIS_ABSPATH/$TEST_TYPE/local"

  echo "TEST: $TEST_TYPE 1 pre"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE pre"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: $TEST_TYPE 2 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: $TEST_TYPE 3 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  $gitLog

  echo 'TEST: 4 minor'
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE minor"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: $TEST_TYPE 5 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  $gitLog

  echo 'TEST: 6 patch'
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE patch"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: $TEST_TYPE 7 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  $gitLog

  git checkout master

  echo "TEST: $TEST_TYPE 8 pre"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE pre"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: $TEST_TYPE 9 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  $gitLog
)

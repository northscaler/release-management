#!/usr/bin/env bash
set -e

TEST_TYPE="$1"
THIS_ABSPATH="$(
  cd "$(dirname "$0")"
  pwd
)"

SCRIPT="${SCRIPT:-release.sh}"
PREFIX="${PREFIX:-$THIS_ABSPATH/../..}"

OPTS='--pre-rc --verbose'
if echo "$TEST_TYPE" | grep -Eq helm; then
  OPTS="$OPTS --helm-chart-dir release-test-chart"
fi

# TODO: saddy paths

gitLog="git log --pretty=format:%D#%s"
gitLastMsg='git log --pretty="%s"  HEAD^..HEAD'

. "$THIS_ABSPATH/../assertions.sh"

getVersionFile() {
  local prefix="$THIS_ABSPATH/$TEST_TYPE/local"
  case $1 in
  docker)
    echo "$prefix/Dockerfile"
    ;;
  csharp)
    echo "$prefix/AssemblyInfo.cs"
    ;;
  gradle)
    echo "$prefix/build.gradle"
    ;;
  gradlekts)
    echo "$prefix/build.gradle.kts"
    ;;
  maven)
    echo "$prefix/pom.xml"
    ;;
  helm)
    echo "$prefix/release-test-chart"
    ;;
  nodejs)
    echo "$prefix/"
    ;;
  scala)
    echo "$prefix/build.sbt"
    ;;
  version)
    echo "$prefix/VERSION"
    ;;
  esac
}

(
  cd "$THIS_ABSPATH/$TEST_TYPE/local"

  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.0-pre.3
  done

  echo "TEST: $TEST_TYPE 1 pre"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE pre"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.0-pre.4
  done
  assertBranch master
  assertGitLog 1 message 'bump to 1.2.0-pre.4'
  assertGitLog 2 message 'release 1.2.0-pre.3'
  assertGitLog 2 tag '1.2.0-pre.3$'

  echo "TEST: $TEST_TYPE 2 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.0-rc.1
  done
  assertBranch v1.2
  assertGitLog 1 message 'bump to 1.2.0-rc.1'
  assertGitLog 2 message 'release 1.2.0-rc.0'
  assertGitLog 2 tag '1.2.0-rc.0$'

  echo "TEST: $TEST_TYPE 3 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.0-rc.2
  done
  assertBranch v1.2
  assertGitLog 1 message 'bump to 1.2.0-rc.2'
  assertGitLog 2 message 'release 1.2.0-rc.1'
  assertGitLog 2 tag '1.2.0-rc.1$'

  echo "TEST: $TEST_TYPE 4 minor"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE minor"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.1-rc.0
  done
  assertBranch v1.2
  assertGitLog 1 message 'bump to 1.2.1-rc.0'
  assertGitLog 2 message 'release 1.2.0$'
  assertGitLog 2 tag '1.2.0$'

  echo "TEST: $TEST_TYPE 5 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.1-rc.1
  done
  assertBranch v1.2
  assertGitLog 1 message 'bump to 1.2.1-rc.1'
  assertGitLog 2 message 'release 1.2.1-rc.0'
  assertGitLog 2 tag '1.2.1-rc.0$'

  echo "TEST: $TEST_TYPE 6 patch"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE patch"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.2-rc.0
  done
  assertBranch v1.2
  assertGitLog 1 message 'bump to 1.2.2-rc.0'
  assertGitLog 2 message 'release 1.2.1$'
  assertGitLog 2 tag '1.2.1$'

  echo "TEST: $TEST_TYPE 7 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.2.2-rc.1
  done
  assertBranch v1.2
  assertGitLog 1 message 'bump to 1.2.2-rc.1'
  assertGitLog 2 message 'release 1.2.2-rc.0$'
  assertGitLog 2 tag '1.2.2-rc.0$'

  git checkout master

  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.3.0-pre.0
  done

  echo "TEST: $TEST_TYPE 8 pre"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE pre"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.3.0-pre.1
  done
  assertBranch master
  assertGitLog 1 message 'bump to 1.3.0-pre.1'
  assertGitLog 2 message 'release 1.3.0-pre.0$'
  assertGitLog 2 tag '1.3.0-pre.0$'

  echo "TEST: $TEST_TYPE 9 rc"
  cmd="$PREFIX/$SCRIPT $OPTS --tech $TEST_TYPE rc"
  echo $cmd
  $cmd
  for t in $(echo "$TEST_TYPE" | tr ',' ' '); do
    assertVersion $t "$(getVersionFile $t)" 1.3.0-rc.1
  done
  assertBranch v1.3
  assertGitLog 1 message 'bump to 1.3.0-rc.1'
  assertGitLog 2 message 'release 1.3.0-rc.0$'
  assertGitLog 2 tag '1.3.0-rc.0$'
)

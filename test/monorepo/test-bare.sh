#!/usr/bin/env bash
set -e

THIS_ABSPATH="$(
  cd "$(dirname "$0")"
  pwd
)"

export NO_USE_LOCAL_NODEJS=1
export NO_USE_LOCAL_NPM=1
export NO_USE_LOCAL_FX=1
export NO_USE_LOCAL_YMLX=1
export NO_USE_LOCAL_MATCH=1

SCRIPT="${SCRIPT:-release.sh}"
PREFIX="${PREFIX:-$THIS_ABSPATH/../..}"

OPTS="\
  --verbose \
  --dev-qa \
  --csharp-file csharp/project-1/AssemblyInfo.cs \
  --csharp-file csharp/project-2/AssemblyInfo.2.cs \
  --docker-file docker/project-1/Dockerfile:docker/project-2/project-2.Dockerfile \
  --gradle-file gradle/project-1/build.gradle:gradle/project-2/build.2.gradle \
  --gradlekts-file gradlekts/project-1/build.gradle.kts:gradlekts/project-2/build.gradle.2.kts \
  --helm-chart-dir helm/project-1/release-test-chart:helm/project-2/release-test-chart2 \
  --maven-file maven/project-1/pom.xml:maven/project-2/pom.2.xml \
  --nodejs-dir nodejs/project-1:nodejs/project-2 \
  --scala-file scala/project-1/build.sbt:scala/project-2/build.2.sbt \
  --version-file version/project-1/VERSION:version/project-2/VERSION2 \
  "

MAIN=dev
PRE=dev
RC=qa
# export RM_DEBUG=1

# TODO: test assertions & saddy paths

gitLog='git log --pretty=oneline'
gitLastMsg='git log --pretty="%s"  HEAD^..HEAD'

(
  cd "$THIS_ABSPATH/local"

  echo "TEST: 1 $PRE"
  cmd="$PREFIX/$SCRIPT $OPTS $PRE"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: 2 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: 3 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  $gitLog

  echo 'TEST: 4 minor'
  cmd="$PREFIX/$SCRIPT $OPTS minor"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: 5 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  $gitLog

  echo 'TEST: 6 patch'
  cmd="$PREFIX/$SCRIPT $OPTS patch"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: 7 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  $gitLog

  git checkout $MAIN

  echo "TEST: 8 $PRE"
  cmd="$PREFIX/$SCRIPT $OPTS $PRE"
  echo $cmd
  $cmd
  $gitLog

  echo "TEST: 9 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  $gitLog
)

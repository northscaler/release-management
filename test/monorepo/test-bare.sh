#!/usr/bin/env bash
set -e

THIS_ABSPATH="$(cd "$(dirname "$0")"; pwd)"

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
  --csharp-pathname csharp/project-1/AssemblyInfo.cs \
  --csharp-pathname csharp/project-2/AssemblyInfo.2.cs \
  --docker-pathname docker/project-1/Dockerfile:docker/project-2/project-2.Dockerfile \
  --gradle-pathname gradle/project-1/build.gradle:gradle/project-2/build.2.gradle \
  --gradlekts-pathname gradlekts/project-1/build.gradle.kts:gradlekts/project-2/build.gradle.2.kts \
  --helm-pathname helm/project-1/release-test-chart/Chart.yaml:helm/project-2/release-test-chart2/Chart.yaml \
  --maven-pathname maven/project-1/pom.xml:maven/project-2/pom.2.xml \
  --nodejs-dir-pathname nodejs/project-1:nodejs/project-2 \
  --scala-pathname scala/project-1/build.sbt:scala/project-2/build.2.sbt \
  --version-pathname version/project-1/VERSION:version/project-2/VERSION2 \
  "

PRE=dev
RC=qa

# TODO: test assertions & saddy paths

gitLog='git log --pretty=oneline'
gitLastMsg='git log --pretty="%s"  HEAD^..HEAD'

(
  cd "$THIS_ABSPATH/local"

  echo "TEST: 1 $PRE"
  $PREFIX/$SCRIPT $OPTS $PRE
  $gitLog

  echo "TEST: 2 $RC"
  $PREFIX/$SCRIPT $OPTS $RC
  $gitLog

  echo "TEST: 3 $RC"
  $PREFIX/$SCRIPT $OPTS $RC
  $gitLog

  echo 'TEST: 4 minor'
  $PREFIX/$SCRIPT $OPTS minor
  $gitLog

  echo "TEST: 5 $RC"
  $PREFIX/$SCRIPT $OPTS $RC
  $gitLog

  echo 'TEST: 6 patch'
  $PREFIX/$SCRIPT $OPTS patch
  $gitLog

  echo "TEST: 7 $RC"
  $PREFIX/$SCRIPT $OPTS $RC
  $gitLog

  git checkout master

  echo "TEST: 8 $PRE"
  $PREFIX/$SCRIPT $OPTS $PRE
  $gitLog

  echo "TEST: 9 $RC"
  $PREFIX/$SCRIPT $OPTS $RC
  $gitLog
)

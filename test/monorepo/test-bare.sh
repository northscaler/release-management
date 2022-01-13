#!/usr/bin/env bash
set -e

THIS_ABSPATH="$(
  cd "$(dirname "$0")"
  pwd
)"

. "$THIS_ABSPATH/../assertions.sh"

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

# TODO: saddy paths

assertVersions() {
  echo "asserting versions are all $1"

  echo 'asserting csharp versions'
  assertVersion csharp "$THIS_ABSPATH/local/csharp/project-1/AssemblyInfo.cs" $1
  assertVersion csharp "$THIS_ABSPATH/local/csharp/project-2/AssemblyInfo.2.cs" $1

  echo 'asserting docker versions'
  assertVersion docker "$THIS_ABSPATH/local/docker/project-1/Dockerfile" $1
  assertVersion docker "$THIS_ABSPATH/local/docker/project-2/project-2.Dockerfile" $1
  
  echo 'asserting gradle versions'
  assertVersion gradle "$THIS_ABSPATH/local/gradle/project-1/build.gradle" $1
  assertVersion gradle "$THIS_ABSPATH/local/gradle/project-2/build.2.gradle" $1
  
  echo 'asserting gradlekts versions'
  assertVersion gradlekts "$THIS_ABSPATH/local/gradlekts/project-1/build.gradle.kts" $1
  assertVersion gradlekts "$THIS_ABSPATH/local/gradlekts/project-2/build.gradle.2.kts" $1
  
  echo 'asserting helm versions'
  assertVersion helm "$THIS_ABSPATH/local/helm/project-1/release-test-chart" $1
  assertVersion helm "$THIS_ABSPATH/local/helm/project-2/release-test-chart2" $1
  
  echo 'asserting maven versions'
  assertVersion maven "$THIS_ABSPATH/local/maven/project-1/pom.xml" $1
  assertVersion maven "$THIS_ABSPATH/local/maven/project-2/pom.2.xml" $1
  
  echo 'asserting nodejs versions'
  assertVersion nodejs "$THIS_ABSPATH/local/nodejs/project-1" $1
  assertVersion nodejs "$THIS_ABSPATH/local/nodejs/project-2" $1
  
  echo 'asserting scala versions'
  assertVersion scala "$THIS_ABSPATH/local/scala/project-1/build.sbt" $1
  assertVersion scala "$THIS_ABSPATH/local/scala/project-2/build.2.sbt" $1
  
  echo 'asserting version versions'
  assertVersion version "$THIS_ABSPATH/local/version/project-1/VERSION" $1
  assertVersion version "$THIS_ABSPATH/local/version/project-2/VERSION2" $1
}

gitLog='git log --pretty=oneline'
gitLastMsg='git log --pretty="%s"  HEAD^..HEAD'

(
  cd "$THIS_ABSPATH/local"

  assertVersions 2.3.0-dev.0

  echo "TEST: 1 $PRE"
  cmd="$PREFIX/$SCRIPT $OPTS $PRE"
  echo $cmd
  $cmd
  assertVersions 2.3.0-dev.1
  assertBranch $MAIN
  assertGitLog 1 message 'bump to 2.3.0-dev.1'
  assertGitLog 2 message 'release 2.3.0-dev.0'
  assertGitLog 2 tag '2.3.0-dev.0$'

  echo "TEST: 2 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  assertVersions 2.3.0-qa.1
  assertBranch v2.3
  assertGitLog 1 message 'bump to 2.3.0-qa.1'
  assertGitLog 2 message 'release 2.3.0-qa.0'
  assertGitLog 2 tag '2.3.0-qa.0$'

  echo "TEST: 3 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  assertVersions 2.3.0-qa.2
  assertBranch v2.3
  assertGitLog 1 message 'bump to 2.3.0-qa.2'
  assertGitLog 2 message 'release 2.3.0-qa.1'
  assertGitLog 2 tag '2.3.0-qa.1$'

  echo 'TEST: 4 minor'
  cmd="$PREFIX/$SCRIPT $OPTS minor"
  echo $cmd
  $cmd
  assertVersions 2.3.1-qa.0
  assertBranch v2.3
  assertGitLog 1 message 'bump to 2.3.1-qa.0'
  assertGitLog 2 message 'release 2.3.0'
  assertGitLog 2 tag '2.3.0$'

  echo "TEST: 5 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  assertVersions 2.3.1-qa.1
  assertBranch v2.3
  assertGitLog 1 message 'bump to 2.3.1-qa.1'
  assertGitLog 2 message 'release 2.3.1-qa.0'
  assertGitLog 2 tag '2.3.1-qa.0$'

  echo 'TEST: 6 patch'
  cmd="$PREFIX/$SCRIPT $OPTS patch"
  echo $cmd
  $cmd
  assertVersions 2.3.2-qa.0
  assertBranch v2.3
  assertGitLog 1 message 'bump to 2.3.2-qa.0'
  assertGitLog 2 message 'release 2.3.1'
  assertGitLog 2 tag '2.3.1$'

  echo "TEST: 7 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  assertVersions 2.3.2-qa.1
  assertBranch v2.3
  assertGitLog 1 message 'bump to 2.3.2-qa.1'
  assertGitLog 2 message 'release 2.3.2-qa.0'
  assertGitLog 2 tag '2.3.2-qa.0$'

  git checkout $MAIN
  assertVersions 2.4.0-dev.0

  echo "TEST: 8 $PRE"
  cmd="$PREFIX/$SCRIPT $OPTS $PRE"
  echo $cmd
  $cmd
  assertVersions 2.4.0-dev.1
  assertBranch $MAIN
  assertGitLog 1 message 'bump to 2.4.0-dev.1'
  assertGitLog 2 message 'release 2.4.0-dev.0'
  assertGitLog 2 tag '2.4.0-dev.0$'

  echo "TEST: 9 $RC"
  cmd="$PREFIX/$SCRIPT $OPTS $RC"
  echo $cmd
  $cmd
  assertVersions 2.4.0-qa.1
  assertBranch v2.4
  assertGitLog 1 message 'bump to 2.4.0-qa.1'
  assertGitLog 2 message 'release 2.4.0-qa.0'
  assertGitLog 2 tag '2.4.0-qa.0$'
)

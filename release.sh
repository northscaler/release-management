#!/usr/bin/env bash
# MIT License
#
# Copyright (c) 2022 Northscaler, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# See https://gitlab.com/northscaler-public/release-management/-/blob/dev/readme.md for more information.

# This script implements a minor-release-per-branch workflow projects using git for source control.
# It supports many different technologies by using low-tech means (sed, awk, etc) to manage version strings.

# Version strings are assumed to follow https://semver.org semantics.

# New features are only go into the main branch.
# Once a release branch is created for a new minor release, only patches should be committed to that release branch, and
# in most cases, each patch should be cherry-picked back to the main branch.

# Release prereleases of new features from your main branch whenever you want to.

# When you decide that you're feature complete in main for your next release and are ready for QA testing, perform a
# release candidate (RC) release from the main branch.  This will create the minor release branch and perform the RC
# release in that release branch, advancing versions appropriately in both your main & release branches.

# Now, development of new features can continue in the main branch while you bugfix and release more RCs from the
# release branch.  Remember, you usually cherry-pick changes from the release branch back to the main branch.

# When you decide that you're bug-free enough for your first generally available (GA) release, perform a minor release
# from your release branch.  At that point, you can continue fixing bugs in the release branch, issuing subsequent RC
# releases (and cherry-picking back to the main branch) until you're ready for your first patch release.  Issue the
# patch release, continue bug fixing & releasing patches, repeating ad nauseum.

# Note that a major release is technically the same as a minor release, just that the minor
# component of the version string is literally "0".

# NB: The 'RM_' prefix in environment variables below stands for "Release Management".

set -e

RM_DEBUG=${RM_DEBUG:-""}

RM_ERR_INVOCATION=1
RM_ERR_VERSIONS=2
RM_ERR_GIT_STATE=3

THIS_ABSPATH="$(realpath "$0")"

verbose() {
  if [ -n "$RM_VERBOSE" ]; then
    echo "$1"
  fi
}

MATCH=match
if ! which $MATCH; then
  MATCH="docker run --rm -i matthewadams12/$MATCH"
fi

YMLX=ymlx
if ! which $YMLX; then
  export YMLX="docker run --rm -i matthewadams12/$YMLX"
fi

XMLSTARLET=xmlstarlet
if ! which $XMLSTARLET; then
  export XMLSTARLET="docker run --rm -i jakubsacha/docker-$XMLSTARLET"
fi

RM_ORIGIN=${RM_ORIGIN:-origin}
RM_MAIN=${RM_MAIN:-main}
RM_TAG_PREFIX=${RM_TAG_PREFIX:-''}
RM_TAG_SUFFIX=${RM_TAG_SUFFIX:-''}
RM_BRANCH_PREFIX=${RM_BRANCH_PREFIX:-'v'}
RM_BRANCH_SUFFIX=${RM_BRANCH_SUFFIX:-''}     # '.x' is a common one
RM_GIT_COMMIT_OPTS=${RM_GIT_COMMIT_OPTS:-''} # --no-verify is a common one
RM_GIT_PUSH_OPTS=${RM_GIT_PUSH_OPTS:-''}     # --no-verify is a common one
RM_DEFAULT_PRE=${RM_DEFAULT_PRE:-$RM_MAIN}
RM_DEFAULT_RC=${RM_DEFAULT_RC:-rc}
RM_PRE=${RM_PRE:-$RM_DEFAULT_PRE}
RM_RC=${RM_RC:-$RM_DEFAULT_RC}
RM_VERBOSE=${RM_VERBOSE:-''}
RM_CHERRY_PICK_FIRST_RC_COMMIT_TO_MAIN=1

#####
##### begin Helm Chart support
#####
RM_HELM_CHART_DIR=${RM_HELM_CHART_DIR:-$(pwd)}
RM_HELM_CHART_FILE="${RM_HELM_CHART_FILE:-Chart.yaml}"

getVersion_helm() {
  set -x
  local RM_HELM_CHART_FILE_PATHNAME="${1:-$RM_HELM_CHART_DIR/$RM_HELM_CHART_FILE}"

  cat "$RM_HELM_CHART_FILE_PATHNAME" | eval "$YMLX this.version"
  set +x
}

setVersion_helm() {
  local V=$1
  local RM_HELM_CHART_FILE_PATHNAME="${2:-$RM_HELM_CHART_DIR/$RM_HELM_CHART_FILE}"
  local FC="$(cat $RM_HELM_CHART_FILE_PATHNAME)"

  echo "$FC" \
    | eval "$YMLX 'it => { it.version = \"$V\"; return it; }'" \
    > "$RM_HELM_CHART_FILE_PATHNAME"

  verbose "$RM_HELM_CHART_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_HELM_CHART_FILE_PATHNAME")"
}
#####
##### end Helm Chart support
#####

#####
##### begin C# support
#####
RM_CSHARP_DIR="${RM_CSHARP_DIR:-$(pwd)}"
RM_CSHARP_FILE="${RM_CSHARP_FILE:-AssemblyInfo.cs}"
RM_CSHARP_ENTRY="${RM_CSHARP_ENTRY:-AssemblyInformationalVersion}"

getVersion_csharp() {
  local RM_CSHARP_FILE_PATHNAME="${1:-$RM_CSHARP_DIR/$RM_CSHARP_FILE}"

  cat "$RM_CSHARP_FILE_PATHNAME" | grep "$RM_CSHARP_ENTRY" | $MATCH \".*\" | sed 's/"//g'
}

setVersion_csharp() {
  local VER="$(echo "$1" | $MATCH '([0-9]{1,}\.[0-9]{1,}\.[0-9]{1,})' | awk '{print $2}')"
  local AFV="$VER.0"
  local AV="$VER.*"

  local RM_CSHARP_FILE_PATHNAME="${2:-$RM_CSHARP_DIR/$RM_CSHARP_FILE}"
  local FC="$(cat "$RM_CSHARP_FILE_PATHNAME")"

  echo "$FC" \
  | sed "s/AssemblyFileVersion.*/AssemblyFileVersion\(\"$AFV\"\)]/" \
  | sed "s/AssemblyVersion.*/AssemblyVersion\(\"$AV\"\)]/" \
  | sed "s/$RM_CSHARP_ENTRY.*/$RM_CSHARP_ENTRY\(\"$1\"\)]/" \
  > "$RM_CSHARP_FILE_PATHNAME"

  verbose "$RM_CSHARP_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_CSHARP_FILE_PATHNAME")"
}
#####
##### end C# support
#####

#####
##### begin gradle support
#####
RM_GRADLE_DIR="${RM_GRADLE_DIR:-$(pwd)}"
RM_GRADLE_FILE="${RM_GRADLE_FILE:-build.gradle}"

getVersion_gradle() {
  local RM_GRADLE_FILE_PATHNAME="${1:-$RM_GRADLE_DIR/$RM_GRADLE_FILE}"

  cat "$RM_GRADLE_FILE_PATHNAME" | egrep "^version" | $MATCH \'.*\' | sed "s/'//g"
}

setVersion_gradle() {
  local RM_GRADLE_FILE_PATHNAME="${2:-$RM_GRADLE_DIR/$RM_GRADLE_FILE}"
  local V=$1
  local FC="$(cat "$RM_GRADLE_FILE")"

  echo "$FC" \
  | sed "s/^version.*/version = \'$V\'/" \
  > "$RM_GRADLE_FILE_PATHNAME"

  verbose "$RM_GRADLE_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_GRADLE_FILE_PATHNAME")"
}
#####
##### end gradle support
#####

#####
##### begin gradlekts support
#####
RM_GRADLE_KOTLIN_DIR="${RM_GRADLE_KOTLIN_DIR:-$(pwd)}"
RM_GRADLE_KOTLIN_FILE="${RM_GRADLE_KOTLIN_FILE:-build.gradle.kts}"

getVersion_gradlekts() {
  local RM_GRADLE_KOTLIN_FILE_PATHNAME="${1:-$RM_GRADLE_KOTLIN_DIR/$RM_GRADLE_KOTLIN_FILE}"

  cat "$RM_GRADLE_KOTLIN_FILE_PATHNAME" | egrep "^version" | egrep -o "['\"].*['\"]" | tr '"' ' ' | tr "'" ' ' | xargs
}

# usage: setVersion version
setVersion_gradlekts() {
  local V=$1
  local FC="$(cat "$RM_GRADLE_KOTLIN_FILE")"
  local RM_GRADLE_KOTLIN_FILE_PATHNAME="${2:-$RM_GRADLE_KOTLIN_DIR/$RM_GRADLE_KOTLIN_FILE}"

  echo "$FC" \
  | sed "s/^version.*/version = \"$V\"/" \
  > "$RM_GRADLE_KOTLIN_FILE_PATHNAME"

  verbose "$RM_GRADLE_KOTLIN_FILE_PATHNAME is now:"
  verbose "$(cat cat "$RM_GRADLE_KOTLIN_FILE_PATHNAME")"
}
#####
##### end gradlekts support
#####

#####
##### begin Docker image support
#####
RM_DOCKER_DIR="${RM_DOCKER_DIR:-$(pwd)}"
RM_DOCKER_FILE="${RM_DOCKER_FILE:-Dockerfile}"
RM_DOCKER_VERSION_LABEL="${RM_DOCKER_VERSION_LABEL:-version}"

getVersion_docker() {
  set -x
  local RM_DOCKER_FILE_PATHNAME="${1:-$RM_DOCKER_DIR/$RM_DOCKER_FILE}"

  echo "$(egrep '^LABEL' "$RM_DOCKER_FILE_PATHNAME" | egrep -o "$RM_DOCKER_VERSION_LABEL=\"?[0-9]+\.[0-9]+\.[0-9]+(-[^ \"]*)?\"?" | cut -d'=' -f2 | sed 's/"//g')"
  set +x
}

setVersion_docker() {
  set -x
  local V=$1
  local label
  local first=true
  local RM_DOCKER_FILE_PATHNAME="${2:-$RM_DOCKER_DIR/$RM_DOCKER_FILE}"
  local lines

  printf "$(cat "$RM_DOCKER_FILE_PATHNAME")\n" | while read line; do
    label="$(echo "$line"  | egrep '^LABEL' | egrep "$RM_DOCKER_VERSION_LABEL=\"?[0-9]+\.[0-9]+\.[0-9]+(-[^ \"]*)?\"?" || true)"
    if [ -z "$label" ]; then # skip it
      if [ $first = true ]; then
        first=false
        lines="$line"
      else
        lines="$lines\n$line"
      fi
    else # we found the LABEL line with the version=<semver> in it; replace & append to lines
      line="$(echo "$label" | sed -E "s/$RM_DOCKER_VERSION_LABEL=\"?[0-9]+\.[0-9]+\.[0-9]+(-[^ \"]*)?\"?/$RM_DOCKER_VERSION_LABEL=$1/")"
      lines="$lines\n$line"
    fi
    printf "$lines" > "$RM_DOCKER_FILE_PATHNAME"
  done
  lines="$(cat "$RM_DOCKER_FILE_PATHNAME")\n"
  printf "$lines" > "$RM_DOCKER_FILE_PATHNAME"

  verbose "$RM_DOCKER_FILE_PATHNAME is now:"
  verbose "$(cat cat "$RM_DOCKER_FILE_PATHNAME")"
  set +x
}
#####
##### end Docker image support
#####

#####
##### begin Maven pom.xml support
#####
RM_MAVEN_DIR="${RM_MAVEN_DIR:-$(pwd)}"
RM_MAVEN_FILE="${RM_MAVEN_FILE:-pom.xml}"

getVersion_maven() {
  local RM_MAVEN_FILE_PATHNAME="${1:-$RM_MAVEN_DIR/$RM_MAVEN_FILE}"

  cat "$RM_MAVEN_FILE_PATHNAME" | eval "$XMLSTARLET sel -N x=http://maven.apache.org/POM/4.0.0 -t -v /x:project/x:version -"
}

setVersion_maven() {
  local V=$1
  local RM_MAVEN_FILE_PATHNAME="${2:-$RM_MAVEN_DIR/$RM_MAVEN_FILE}"

  cat "$RM_MAVEN_FILE_PATHNAME" | eval "$XMLSTARLET ed -P -N x=http://maven.apache.org/POM/4.0.0 -u /x:project/x:version -v $V" > "$RM_MAVEN_FILE_PATHNAME.tmp"
  mv "$RM_MAVEN_FILE_PATHNAME.tmp" "$RM_MAVEN_FILE_PATHNAME"

  verbose "$RM_MAVEN_FILE is now:"
  verbose "$(cat "$RM_MAVEN_FILE")"
}
#####
##### end Maven pom.xml support
#####

#####
##### begin nodejs package.json support
#####
RM_NODEJS_DIR="${RM_NODEJS_DIR:-$(pwd)}"
RM_NODEJS_PACKAGE_JSON="${RM_NODEJS_PACKAGE_JSON:-package.json}"

getVersion_nodejs() {
  local RM_NODEJS_DIR="${1:-$RM_NODEJS_DIR}"
  # make an absolute path
  RM_NODEJS_DIR="$(cd "$RM_NODEJS_DIR" && pwd)"

  local RM_NODEJS_DOCKER="docker run --rm -i -v $RM_NODEJS_DIR:/cwd -w /cwd node"
  local RM_NODEJS_NODE=node
  if [ -n "$NO_USE_LOCAL_NODEJS" ] || ! $RM_NODEJS_NODE --version >/dev/null 2>&1; then
    RM_NODEJS_NODE="$RM_NODEJS_DOCKER node"
  fi

  (cd "$RM_NODEJS_DIR" && $RM_NODEJS_NODE -e 'console.log(require("./package.json").version)')
}

setVersion_nodejs() {
  local V=$1
  local RM_NODEJS_DIR="${2:-$RM_NODEJS_DIR}"
  # make an absolute path
  RM_NODEJS_DIR="$(cd "$RM_NODEJS_DIR" && pwd)"
  local RM_NODEJS_FILE_PATHNAME="$RM_NODEJS_DIR/$RM_NODEJS_PACKAGE_JSON"
  local RM_NODEJS_DOCKER="docker run --rm -i -v $RM_NODEJS_DIR:/cwd -w /cwd node"

  local RM_NODEJS_NODE=node
  if [ -n "$NO_USE_LOCAL_NODEJS" ] || ! $RM_NODEJS_NODE --version >/dev/null 2>&1; then
    RM_NODEJS_NODE="$RM_NODEJS_DOCKER node"
  fi

  RM_NODEJS_NPM=npm
  if [ -n "$NO_USE_LOCAL_NPM" ] || ! $RM_NODEJS_NPM --version >/dev/null 2>&1; then
    RM_NODEJS_NPM="$RM_NODEJS_DOCKER npm"
  fi

  (cd "$RM_NODEJS_DIR" && $RM_NODEJS_NPM version --no-git-tag-version --allow-same-version $V)

  verbose "$RM_NODEJS_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_NODEJS_FILE_PATHNAME")"
}
#####
##### end nodejs package.json support
#####

#####
##### begin Scala SBT support
#####
RM_SCALA_SBT_DIR="${RM_SCALA_SBT_DIR:-$(pwd)}"
RM_SCALA_SBT_FILE="${RM_SCALA_SBT_FILE:-build.sbt}"

getVersion_sbt() {
  local RM_SCALA_SBT_FILE_PATHNAME="${1:-$RM_SCALA_SBT_DIR/$RM_SCALA_SBT_FILE}"

  cat "$RM_SCALA_SBT_FILE_PATHNAME" | egrep "^version\s*\:\=.*" | $MATCH \".*\" | sed 's/"//g'
}

setVersion_sbt() {
  local V=$1
  local RM_SCALA_SBT_FILE_PATHNAME="${2:-$RM_SCALA_SBT_DIR/$RM_SCALA_SBT_FILE}"
  local FC="$(cat "$RM_SCALA_SBT_FILE_PATHNAME")"

  echo "$FC" \
  | sed "s/^version.*/version := \"$V\"/" \
  > "$RM_SCALA_SBT_FILE_PATHNAME"

  verbose "$RM_SCALA_SBT_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_SCALA_SBT_FILE_PATHNAME")"
}
#####
##### end Scala SBT support
#####

#####
##### begin VERSION file support
#####
RM_VERSION_DIR="${RM_VERSION_DIR:-$(pwd)}"
RM_VERSION_FILE="${RM_VERSION_FILE:-VERSION}"

getVersion_version() {
  local RM_VERSION_FILE_PATHNAME="${1:-$RM_VERSION_DIR/$RM_VERSION_FILE}"

  cat "$RM_VERSION_FILE_PATHNAME" | xargs
}

setVersion_version() {
  local V=$1
  local RM_VERSION_FILE_PATHNAME="${2:-$RM_VERSION_DIR/$RM_VERSION_FILE}"

  echo "$V" > "$RM_VERSION_FILE_PATHNAME"

  verbose "$RM_VERSION_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_VERSION_FILE_PATHNAME")"
}
#####
##### end VERSION file support
#####

usage() {
  echo "This script performs release commits, tags & branching.  Usage:"

  printf "%s [--tech tech1,tech2,...] [options] $RM_PRE|$RM_RC|minor|patch\n \
  where options are as follows (last one wins):\n \
  --tech|-t                                 # required or implied at least once, the technology types to release (comma-delimited list ok); choose from:\n \
                                            #  'helm' for Helm Chart (Chart.yaml),\n \
                                            #  'docker' for Docker Image (Dockerfile),\n \
                                            #  'nodejs' for Node.js (package.json),\n \
                                            #  'csharp' for C# (AssemblyInformationalVersion in AssemblyInfo.cs),\n \
                                            #  'scala' for Scala (build.sbt),\n \
                                            #  'gradle' for Gradle (build.gradle),\n \
                                            #  'gradlekts' for Kotlin Gradle (build.gradle.kts),\n \
                                            #  'maven' for Maven XML (pom.xml),\n \
                                            #  'version' for plain text version file (VERSION),\n \
  [--origin|-o origin]                      # optional, git origin, default '%s'\n \
  [--main|-m main]                          # optional, git main branch, default '%s'\n \
  [--cherry-pick-to-main]                   # optional, cherry pick release commit to main branch, default true\n \
  [--no-cherry-pick-to-main]                # optional, don't cherry pick release commit to main branch, default false\n \
  [--release-tag-prefix|-p prefix]          # optional, git release tag prefix, default '%s'\n \
  [--release-tag-suffix|-s suffix]          # optional, git release tag suffix, default  '%s'\n \
  [--release-branch-prefix|-P prefix]       # optional, git release branch prefix, default '%s'\n \
  [--release-branch-suffix|-S suffix]       # optional, git release branch suffix, default '%s' ('.x' is common)\n \
  [--git-commit-opts|-o opts]               # optional, git commit options, default '%s' ('--no-verify' is common)\n \
  [--git-push-opts|-O opts]                 # optional, git commit options, default '%s' ('--no-verify' is common)\n \
  [--pre-release-token|-k token]            # optional, pre release token, default '%s'\n \
  [--rc-release-token|-K token]             # optional, release candidate release token, default '%s'\n \
  [--dev-qa]                                # optional, shortcut for '--main dev --pre-release-token dev --rc-release-token qa'\n \
  [--trunk-qa]                              # optional, shortcut for '--main trunk --pre-release-token trunk --rc-release-token qa'\n \
  [--alpha-beta]                            # optional, shortcut for '--main alpha --pre-release-token alpha --rc-release-token beta'\n \
  [--pre-rc]                                # optional, shortcut for '--main master --pre-release-token pre --rc-release-token rc' (legacy behavior)\n \
  [--helm-chart-dir chartDir]               # optional, chart directory, implies '--tech helm', default cwd ('%s')\n \
  [--helm-chart-file chartFile]             # optional, chart filename, implies '--tech helm', default '%s'\n \
  [--helm-chart-pathname chartPathnames]    # optional, colon-separated pathname(s) to chart files, implies '--tech helm', default '%s'\n \
  [--csharp-file csharpFile]                # optional, csharp filename, implies '--tech csharp', default '%s'\n \
  [--csharp-pathname csharpPathnames]       # optional, colon-separated pathname(s) to csharp files, implies '--tech csharp', default '%s'\n \
  [--gradle-file gradleFile]                # optional, gradle filename, implies '--tech gradle', default '%s'\n \
  [--gradle-pathname gradlePathnames]       # optional, colon-separated pathname(s) to gradle files, implies '--tech gradle', default '%s'\n \
  [--gradlekts-file gradlektsFile]          # optional, gradlekts filename, implies '--tech gradlekts', default '%s'\n \
  [--gradlekts-pathname gradlektsPathnames] # optional, colon-separated pathname(s) to gradlekts files, implies '--tech gradlekts', default '%s'\n \
  [--docker-file dockerFile]                # optional, docker filename, implies '--tech docker', default '%s'\n \
  [--docker-file-version-label label]       # optional, docker file version label, implies '--tech docker', default '%s'\n \
  [--docker-pathname dockerPathnames]       # optional, colon-separated pathname(s) to docker files, implies '--tech docker', default '%s'\n \
  [--maven-file mavenFile]                  # optional, maven POM filename, implies '--tech maven', default '%s'\n \
  [--maven-pathname mavenPathnames]         # optional, colon-separated pathname(s) to maven files, implies '--tech maven', default '%s'\n \
  [--nodejs-file packageJson]               # optional, nodejs filename, implies '--tech nodejs', default '%s'\n \
  [--nodejs-pathname nodejsPathnames]       # optional, colon-separated pathname(s) to nodejs files, implies '--tech nodejs', default '%s'\n \
  [--scala-file buildSbt]                   # optional, scala filename, implies '--tech scala', default '%s'\n \
  [--scala-pathname scalaPathnames]         # optional, colon-separated pathname(s) to scala files, implies '--tech scala', default '%s'\n \
  [--version-file versionFile]              # optional, version filename, implies '--tech version', default '%s'\n \
  [--version-pathname versionPathnames]     # optional, colon-separated pathname(s) to version files, implies '--tech version', default '%s'\n \
  [--verbose|-v]                            # optional, displays detailed progress\n \
  [--help|-h]                               # optional, displays usage\n" \
    "$0" \
    "$RM_ORIGIN" \
    "$RM_MAIN" \
    "$RM_TAG_PREFIX" \
    "$RM_TAG_SUFFIX" \
    "$RM_BRANCH_PREFIX" \
    "$RM_BRANCH_SUFFIX" \
    "$RM_GIT_COMMIT_OPTS" \
    "$RM_GIT_PUSH_OPTS" \
    "$RM_PRE" \
    "$RM_RC" \
    "$RM_HELM_CHART_DIR" \
    "$RM_HELM_CHART_FILE" \
    "$RM_HELM_CHART_DIR/$RM_HELM_CHART_FILE" \
    "$RM_CSHARP_FILE" \
    "$RM_CSHARP_DIR/$RM_CSHARP_FILE" \
    "$RM_GRADLE_FILE" \
    "$RM_GRADLE_DIR/$RM_GRADLE_FILE" \
    "$RM_GRADLE_KOTLIN_FILE" \
    "$RM_GRADLE_KOTLIN_DIR/$RM_GRADLE_KOTLIN_FILE" \
    "$RM_DOCKER_FILE" \
    "$RM_DOCKER_VERSION_LABEL" \
    "$RM_DOCKER_DIR/$RM_DOCKER_FILE" \
    "$RM_MAVEN_FILE" \
    "$RM_MAVEN_DIR/$RM_MAVEN_FILE" \
    "$RM_NODEJS_PACKAGE_JSON" \
    "$RM_NODEJS_DIR/$RM_NODEJS_PACKAGE_JSON_FILE" \
    "$RM_SCALA_SBT_FILE" \
    "$RM_SCALA_DIR/$RM_SCALA_FILE" \
    "$RM_VERSION_FILE" \
    "$RM_VERSION_DIR/$RM_VERSION_FILE"
}

debug() {
  if [ -n "$RM_DEBUG" ]; then
    echo "$*" >&2
  fi
}

# process args
while [ $# -gt 0 ]; do
  debug "args: $*"

  case "$1" in
  --tech | -t)
    shift
    RM_TECH="$RM_TECH,$1"
    shift
    ;;
  --origin | -o)
    shift
    RM_ORIGIN="$1"
    shift
    ;;
  --main | -m)
    shift
    RM_MAIN="$1"
    shift
    ;;
  --release-tag-prefix | -p)
    shift
    RM_TAG_PREFIX="$1"
    shift
    ;;
  --release-tag-suffix | -s)
    shift
    RM_TAG_SUFFIX="$1"
    shift
    ;;
  --release-branch-prefix | -P)
    shift
    RM_BRANCH_PREFIX="$1"
    shift
    ;;
  --release-branch-suffix | -S)
    shift
    RM_BRANCH_SUFFIX="$1"
    shift
    ;;
  --pre-release-token | -k)
    shift
    RM_PRE="$1"
    shift
    ;;
  --rc-release-token | -K)
    shift
    RM_RC="$1"
    shift
    ;;
  --dev-qa)
    shift
    RM_MAIN=dev
    RM_PRE=$RM_MAIN
    RM_RC=qa
    ;;
  --trunk-qa)
    shift
    RM_MAIN=trunk
    RM_PRE=$RM_MAIN
    RM_RC=qa
    ;;
  --alpha-beta)
    shift
    RM_MAIN=alpha
    RM_PRE=$RM_MAIN
    RM_RC=beta
    ;;
  --pre-rc)
    shift
    RM_MAIN=master
    RM_PRE=pre
    RM_RC=rc
    ;;
  --verbose | -v)
    shift
    RM_VERBOSE=1
    ;;
  --cherry-pick-to-main)
    shift
    RM_CHERRY_PICK_FIRST_RC_COMMIT_TO_MAIN=1
    ;;
  --no-cherry-pick-to-main)
    shift
    RM_CHERRY_PICK_FIRST_RC_COMMIT_TO_MAIN=
    ;;
  --helm-chart-dir)
    shift
    RM_HELM_CHART_DIR="$1"
    shift
    RM_PATHNAMES_chart="" # negates any prior --helm-chart-pathname args
    RM_TECH="$RM_TECH,helm"
    ;;
  --helm-chart-file)
    shift
    RM_HELM_CHART_FILE="$1"
    shift
    RM_PATHNAMES_helm="" # negates any prior --helm-chart-pathname args
    RM_TECH="$RM_TECH,helm"
    ;;
  --helm-chart-pathname)
    shift
    RM_PATHNAMES_helm=":$RM_PATHNAMES_helm:$1"
    shift
    RM_TECH="$RM_TECH,helm"
    ;;
  --csharp-file)
    shift
    RM_CSHARP_FILE="$1"
    shift
    RM_PATHNAMES_csharp="" # negates any prior --csharp-pathname args
    RM_TECH="$RM_TECH,csharp"
    ;;
  --csharp-pathname)
    shift
    RM_PATHNAMES_csharp=":$RM_PATHNAMES_csharp:$1:"
    shift
    RM_TECH="$RM_TECH,csharp"
    ;;
  --gradle-file)
    shift
    RM_GRADLE_FILE="$1"
    shift
    RM_PATHNAMES_gradle="" # negates any prior --gradle-pathname args
    RM_TECH="$RM_TECH,gradle"
    ;;
  --gradle-pathname)
    shift
    RM_PATHNAMES_gradle="$RM_PATHNAMES_gradle:$1:"
    shift
    RM_TECH="$RM_TECH,gradle"
    ;;
  --gradlekts-file)
    shift
    RM_GRADLE_KOTLIN_FILE="$1"
    shift
    RM_PATHNAMES_gradlekts="" # negates any prior --gradlekts-pathname args
    RM_TECH="$RM_TECH,gradlekts"
    ;;
  --gradlekts-pathname)
    shift
    RM_PATHNAMES_gradlekts="$RM_PATHNAMES_gradlekts:$1:"
    shift
    RM_TECH="$RM_TECH,gradlekts"
    ;;
  --docker-file)
    shift
    RM_DOCKER_FILE="$1"
    shift
    RM_PATHNAMES_docker="" # negates any prior --docker-pathname args
    RM_TECH="$RM_TECH,docker"
    ;;
  --docker-pathname)
    shift
    RM_PATHNAMES_docker=":$RM_PATHNAMES_docker:$1:"
    shift
    RM_TECH="$RM_TECH,docker"
    ;;
  --docker-file-version-label)
    shift
    RM_DOCKER_VERSION_LABEL="$1"
    shift
    RM_TECH="$RM_TECH,docker"
    ;;
  --maven-file)
    shift
    RM_MAVEN_FILE="$1"
    shift
    RM_PATHNAMES_maven="" # negates any prior --maven-pathname args
    RM_TECH="$RM_TECH,maven"
    ;;
  --maven-pathname)
    shift
    RM_PATHNAMES_maven=":$RM_PATHNAMES_maven:$1:"
    shift
    RM_TECH="$RM_TECH,maven"
    ;;
  --scala-file)
    shift
    RM_SCALA_SBT_FILE="$1"
    shift
    RM_PATHNAMES_scala="" # negates any prior --scala-pathname args
    RM_TECH="$RM_TECH,scala"
    ;;
  --scala-pathname)
    shift
    RM_PATHNAMES_scala=":$RM_PATHNAMES_scala:$1:"
    shift
    RM_TECH="$RM_TECH,scala"
    ;;
  --nodejs-file)
    shift
    RM_NODEJS_PACKAGE_JSON="$1"
    shift
    RM_PATHNAMES_nodejs="" # negates any prior --nodejs-pathname args
    RM_TECH="$RM_TECH,nodejs"
    ;;
  --nodejs-pathname)
    shift
    RM_PATHNAMES_nodejs=":$RM_PATHNAMES_nodejs:$1:"
    shift
    RM_TECH="$RM_TECH,nodejs"
    ;;
  --version-file)
    shift
    RM_VERSION_FILE="$1"
    shift
    RM_PATHNAMES_version=""
    RM_TECH="$RM_TECH,version"
    ;;
  --version-pathname)
    shift
    RM_PATHNAMES_version=":$RM_PATHNAMES_version:$1:"
    shift
    RM_TECH="$RM_TECH,version"
    ;;
  --help | -h)
    usage >&2
    exit 0
    ;;
  -*)
    usage >&2
    exit $RM_ERR_INVOCATION
    ;;
  *)
    RM_RELEASE_LEVEL="$*"
    break
    ;;
  esac
done

# purge args
while [ $# -gt 0 ]; do
  debug "purging: $*"
  shift
done

if [ -z "$RM_PATHNAMES_helm" ]; then
  RM_PATHNAMES_helm="$(realpath "$RM_HELM_CHART_DIR/$RM_HELM_CHART_FILE")"
fi
if [ -z "$RM_PATHNAMES_csharp" ]; then
  RM_PATHNAMES_csharp="$(realpath "$RM_CSHARP_DIR/$RM_CSHARP_FILE")"
fi
if [ -z "$RM_PATHNAMES_gradle" ]; then
  RM_PATHNAMES_gradle="$(realpath "$RM_GRADLE_DIR/$RM_GRADLE_FILE")"
fi
if [ -z "$RM_PATHNAMES_gradlekts" ]; then
  RM_PATHNAMES_gradlekts="$(realpath "$RM_GRADLE_KOTLIN_DIR/$RM_GRADLE_KOTLIN_FILE")"
fi
if [ -z "$RM_PATHNAMES_docker" ]; then
  RM_PATHNAMES_docker="$(realpath "$RM_DOCKER_DIR/$RM_DOCKER_FILE")"
fi
if [ -z "$RM_PATHNAMES_maven" ]; then
  RM_PATHNAMES_maven="$(realpath "$RM_MAVEN_DIR/$RM_MAVEN_FILE")"
fi
if [ -z "$RM_PATHNAMES_scala" ]; then
  RM_PATHNAMES_scala="$(realpath "$RM_SCALA_SBT_DIR/$RM_SCALA_SBT_FILE")"
fi
if [ -z "$RM_PATHNAMES_nodejs" ]; then
  RM_PATHNAMES_nodejs="$(realpath "$RM_NODEJS_DIR/$RM_NODEJS_PACKAGE_JSON_FILE")"
fi
if [ -z "$RM_PATHNAMES_version" ]; then
  RM_PATHNAMES_version="$(realpath "$RM_VERSION_DIR/$RM_VERSION_FILE")"
fi

# validations

# ensure at least one tech given
RM_TECHNOLOGIES="$(echo -n "$RM_TECH" | tr ',' '\n' | uniq | xargs)"
if [ -z "$RM_TECHNOLOGIES" ]; then
  echo "ERROR: no technologies given or implied" >&2
  usage >&2
  exit $RM_ERR_INVOCATION
fi

# ensure only one positional argument given & that it's a supported value
case "$RM_RELEASE_LEVEL" in
  minor | patch | "$RM_PRE" | "$RM_RC")
    # ok
    verbose "INFO: release level is $RM_RELEASE_LEVEL"
    ;;
  *)
    echo "ERROR: specify a single release level of $RM_PRE, $RM_RC, minor, or patch" >&2
    usage >&2
    exit $RM_ERR_INVOCATION
    ;;
esac

# ensure pre & rc tokens are not the same
if [ "$RM_PRE" == "$RM_RC" ]; then
  echo "ERROR: pre release token ($RM_PRE) cannot be the same as release candidate release token ($RM_RC)" >&2
  usage >&2
  exit $RM_ERR_INVOCATION
fi

# ensure pre token sorts alphabetically before rc token
if [ "$RM_PRE" \> "$RM_RC" ]; then
  echo "ERROR: pre release token ($RM_PRE) cannot sort alphabetically after release candidate release token ($RM_RC)" >&2
  usage >&2
  exit $RM_ERR_INVOCATION
fi

setVersions() {
  for t in $RM_TECHNOLOGIES; do
    ORIG_IFS="$IFS"
    IFS=':'
    for p in $(eval "echo \$RM_PATHNAMES_$t"); do
      setVersion_$t $1 "$p"
    done
    IFS="$ORIG_IFS"
  done
}

verbose "INFO: invocation ok; checking required preconditions"

git pull $RM_ORIGIN

verbose "checking that all versions are exactly the same"
for t in $RM_TECHNOLOGIES; do
  ORIG_IFS="$IFS"
  IFS=':'
  pathnames="$(eval "echo \$RM_PATHNAMES_$t")"
  for p in $pathnames; do
    fqpn="$(realpath "$p")"
    debug "invoking: getVersion_$t $fqpn"
    v="$(getVersion_$t "$fqpn")"
    verbose "file '$fqpn' has version '$v'"
    if [ -n "$v_last" ] && [ "$v_last" != "$v" ]; then
      echo "ERROR: versions among different version files differ:" >&2
      echo "$t is at $v in $p" >&2
      echo "but" >&2
      echo "$t_last is at $v_last in $p_last" >&2
      exit $RM_ERR_VERSIONS
    fi
    v_last="$v"
    t_last="$t"
    p_last="$p"
  done
  IFS="$ORIG_IFS"
done
RM_VERSION="$v_last"

if ! git diff --exit-code --no-patch; then
  echo 'ERROR: you have modified tracked files; only release from clean directories!' >&2
  exit $RM_ERR_GIT_STATE
else
  verbose 'INFO: no modified tracked files'
fi

if ! git diff --cached --exit-code --no-patch; then
  echo 'ERROR: you have cached modified tracked files; only release from clean directories!' >&2
  exit $RM_ERR_GIT_STATE
else
  verbose 'INFO: no cached modified tracked files'
fi

if [ -n "$(git status -s)" ]; then
  echo 'ERROR: You have unignored untracked files; only release from clean directories!' >&2
  exit $RM_ERR_GIT_STATE
else
  verbose 'INFO: no unignored untracked files'
fi

RM_BRANCH="$(git status | head -n 1 | awk '{ print $3 }')"
if ! $MATCH "^($RM_MAIN|${RM_BRANCH_PREFIX}[0-9]{1,}\.[0-9]{1,}$RM_BRANCH_SUFFIX)$" "$RM_BRANCH"; then # it is not a main or a release branch
  echo "ERROR: you can only release from the $RM_MAIN branch or release branches! You are currently on $RM_BRANCH" >&2
  exit $RM_ERR_GIT_STATE
else
  verbose "INFO: on branch $RM_BRANCH, from which releases are allowed"
fi

if ! git diff --exit-code -no-patch $RM_BRANCH $RM_ORIGIN/$RM_BRANCH; then
  echo "ERROR: Local branch $RM_BRANCH differs from remote branch $RM_ORIGIN/$RM_BRANCH" >&2
  exit $RM_ERR_GIT_STATE
else
  verbose "INFO: no differences between local & remote branch $RM_BRANCH"
fi

if [ "$RM_BRANCH" == "$RM_MAIN" ]; then
  case "$RM_RELEASE_LEVEL" in
    "$RM_PRE"|"$RM_RC")
      # ok
      ;;
    *)
      echo "ERROR: only '$RM_DEFAULT_PRE'/'$RM_PRE' or '$RM_DEFAULT_RC'/'$RM_RC' releases are permitted from the $RM_MAIN branch." >&2
      exit $RM_ERR_GIT_STATE
      ;;
  esac
else # this is a release branch
  case "$RM_RELEASE_LEVEL" in
      "$RM_RC"|patch|minor)
        # ok
        ;;
      *)
        echo "ERROR: only '$RM_DEFAULT_RC'/'$RM_RC', 'patch', or 'minor' releases are permitted from a release branch." >&2
        exit $RM_ERR_GIT_STATE
        ;;
  esac
fi

verbose "INFO: ok to proceed with $RM_RELEASE_LEVEL from branch $RM_BRANCH"

if ! $MATCH "\-($RM_PRE|$RM_RC)\.[0-9]{1,}$" "$RM_VERSION"; then
  echo "ERROR: repository is in an inconsistent state: current version '$RM_VERSION' does not end in a prerelease suffix '$RM_PRE' or '$RM_RC'! You are currently on branch '$RM_BRANCH'." >&2
  exit $RM_ERR_GIT_STATE
fi

# usage: applyChanges message [tag [remote [branch]]]
applyChanges() {
  git add .
  git commit --allow-empty -m "$1" $RM_GIT_COMMIT_OPTS
  verbose "INFO: committed changes with message: '$1'"

  local MSG="INFO: pushed commits"

  if [ -n "$2" ]; then
    tag="$RM_TAG_PREFIX$2$RM_TAG_SUFFIX"
    git tag "$tag"
    verbose "INFO: tagged $tag"
    MSG="$MSG & tags"
  fi

  local SET_UPSTREAM_ARGS=
  if [ -n "$3" ] && [ -n "$4" ]; then
    SET_UPSTREAM_ARGS="-u $3 $4"
    MSG="$MSG & set tracked upstream to '$3/$4'"
  fi

  git push $RM_GIT_PUSH_OPTS $SET_UPSTREAM_ARGS
  git push --tags

  verbose "$MSG"
}

if [ "$RM_BRANCH" == "$RM_MAIN" ]; then # this will be either an rc release resulting in a new release branch, or a pre
  set +e
  RM_MATCHES="$($MATCH "^([0-9]{1,})\.([0-9]{1,})\.0\-$RM_PRE\.([0-9]{1,})$" "$RM_VERSION")"
  set -e
  if [ -z "$RM_MATCHES" ]; then
    echo "ERROR: the version '$RM_VERSION' does not match the format of major.minor.0-$RM_PRE.n required in the $RM_MAIN branch." >&2
    exit $RM_ERR_VERSIONS
  else
    verbose "INFO: version '$RM_VERSION' matches expected format for branch '$RM_BRANCH'"
  fi

  RM_MAJOR="$(echo "$RM_MATCHES" | awk '{ print $2 }')"
  RM_MINOR="$(echo "$RM_MATCHES" | awk '{ print $3 }')"
  RM_PATCH=0
  RM_PRERELEASE="$(echo "$RM_MATCHES" | awk '{ print $4 }')"

  case "$RM_RELEASE_LEVEL" in
  "$RM_RC") # then it's time to create a new release branch
      RM_NEW_RELEASE_BRANCH="$RM_BRANCH_PREFIX$RM_MAJOR.$RM_MINOR$RM_BRANCH_SUFFIX"
      git checkout -b $RM_NEW_RELEASE_BRANCH

      RM_NEW_RELEASE_BRANCH_VERSION="$RM_MAJOR.$RM_MINOR.0-$RM_RC.0"

      setVersions $RM_NEW_RELEASE_BRANCH_VERSION

      applyChanges "release $RM_NEW_RELEASE_BRANCH_VERSION" $RM_NEW_RELEASE_BRANCH_VERSION $RM_ORIGIN $RM_NEW_RELEASE_BRANCH
      verbose "INFO: created release branch '$RM_NEW_RELEASE_BRANCH' and tagged '$RM_NEW_RELEASE_BRANCH_VERSION' for release"

      # return to master branch
      git checkout $RM_MAIN
      verbose "INFO: checked out '$RM_MAIN'"

      if [ -n "$RM_CHERRY_PICK_FIRST_RC_COMMIT_TO_MAIN" ]; then
        git cherry-pick -x $RM_NEW_RELEASE_BRANCH # cherry pick from release branch to get release candidate commit in master
        verbose "INFO: cherry-picked '$RM_NEW_RELEASE_BRANCH' '$RM_RC' commit into '$RM_MAIN'"
      fi

      # advance master version
      RM_NEXT_VERSION="$RM_MAJOR.$(($RM_MINOR+1)).0-$RM_PRE.0"

      setVersions $RM_NEXT_VERSION

      applyChanges "bump to '$RM_NEXT_VERSION' [skip ci]"

      # return to release branch & prepare for next prerelease
      git checkout $RM_NEW_RELEASE_BRANCH
      verbose "INFO: checked out '$RM_NEW_RELEASE_BRANCH'"

      RM_NEXT_RELEASE_BRANCH_VERSION="$RM_MAJOR.$RM_MINOR.0-$RM_RC.1"

      setVersions $RM_NEXT_RELEASE_BRANCH_VERSION

      applyChanges "bump to $RM_NEXT_RELEASE_BRANCH_VERSION [skip ci]"

      verbose "INFO: released '$RM_RC' version '$RM_VERSION' in branch '$RM_NEW_RELEASE_BRANCH' ok."
      exit 0
      ;;

  "$RM_PRE")
      setVersions $RM_VERSION

      applyChanges "release $RM_VERSION" $RM_VERSION

      RM_NEXT_VERSION=$RM_MAJOR.$RM_MINOR.$RM_PATCH-$RM_PRE.$((RM_PRERELEASE+1))

      setVersions $RM_NEXT_VERSION

      applyChanges "bump to $RM_NEXT_VERSION [skip ci]"

      verbose "INFO: released '$RM_PRE' version '$RM_VERSION' in branch '$RM_MAIN' ok."
      exit 0
      ;;
  esac
fi

# If we get this far, we are releasing from a release branch.
set +e
RM_MATCHES="$($MATCH "^([0-9]{1,})\.([0-9]{1,})\.([0-9]{1,})\-$RM_RC\.([0-9]{1,})$" "$RM_VERSION")"
set -e
if [ -z "$RM_MATCHES" ]; then
  echo "ERROR: the version does not match the format of major.minor.patch-$RM_RC.n required in the release branch." >&2
  exit $RM_ERR_VERSIONS
else
  verbose "INFO: version '$RM_VERSION' matches expected format for branch '$RM_BRANCH'"
fi

RM_MAJOR="$(echo "$RM_MATCHES" | awk '{ print $2 }')"
RM_MINOR="$(echo "$RM_MATCHES" | awk '{ print $3 }')"
RM_PATCH="$(echo "$RM_MATCHES" | awk '{ print $4 }')"
RM_PRERELEASE="$(echo "$RM_MATCHES" | awk '{ print $5 }')"

case "$RM_RELEASE_LEVEL" in
  minor|patch)
    # NOTE: A major release is the same as a minor release, only that the minor version is 0.
    if [ "$RM_RELEASE_LEVEL" = "minor" ] && [ "$RM_PATCH" != "0" ]; then
      echo "ERROR: a minor release has already been performed in this release branch; only patch releases are allowed here now." >&2
      exit $RM_ERR_GIT_STATE
    else
      RM_NEXT_RELEASE_BRANCH_VERSION="$RM_MAJOR.$RM_MINOR.1-$RM_RC.0"
    fi
    if [ "$RM_RELEASE_LEVEL" = "patch" ] && [ "$RM_PATCH" = "0" ]; then
      echo "ERROR: you must perform a minor release before releasing a patch in this release branch." >&2
      exit $RM_ERR_GIT_STATE
    else
      RM_NEXT_RELEASE_BRANCH_VERSION="$RM_MAJOR.$RM_MINOR.$((RM_PATCH+1))-$RM_RC.0"
    fi

    verbose "INFO: ok to perform a '$RM_RELEASE_LEVEL' release in branch '$RM_BRANCH'"

    RM_RELEASE_VERSION="$RM_MAJOR.$RM_MINOR.$RM_PATCH"

    setVersions $RM_RELEASE_VERSION

    applyChanges "release $RM_RELEASE_VERSION" $RM_RELEASE_VERSION

    setVersions $RM_NEXT_RELEASE_BRANCH_VERSION

    applyChanges "bump to $RM_NEXT_RELEASE_BRANCH_VERSION [skip ci]"

    verbose "INFO: released '$RM_VERSION' in branch '$RM_BRANCH' ok."
    exit 0
    ;;

  "$RM_RC")
    setVersions $RM_VERSION

    applyChanges "release $RM_VERSION" $RM_VERSION

    RM_NEXT_RELEASE_BRANCH_VERSION="$RM_MAJOR.$RM_MINOR.$RM_PATCH-$RM_RC.$((RM_PRERELEASE+1))"

    setVersions $RM_NEXT_RELEASE_BRANCH_VERSION

    applyChanges "bump to $RM_NEXT_RELEASE_BRANCH_VERSION [skip ci]"

    verbose "INFO: released '$RM_VERSION' in branch '$RM_BRANCH' ok."
    exit 0
    ;;
esac

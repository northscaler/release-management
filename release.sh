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

getVersion_helm() {
  local RM_HELM_CHART_DIR_PATHNAME="$1"

  eval "$YMLX this.version" < "$RM_HELM_CHART_DIR_PATHNAME/Chart.yaml"
}

setVersion_helm() {
  local V=$1
  local RM_HELM_CHART_DIR_PATHNAME="$2"
  local RM_HELM_CHART_FILE_PATHNAME="$RM_HELM_CHART_DIR_PATHNAME/Chart.yaml"
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
  local RM_CSHARP_FILE_PATHNAME="$1"

  cat "$RM_CSHARP_FILE_PATHNAME" | grep -E "$RM_CSHARP_ENTRY" | eval "$MATCH '(\d+\.\d+\.\d+(-.+\.\d+)?)'" | awk '{ print $1 }'
}

setVersion_csharp() {
  local VER="$(echo "$1" | eval "$MATCH '([0-9]{1,}\.[0-9]{1,}\.[0-9]{1,})'" | awk '{print $2}')"
  local AFV="$VER.0"
  local AV="$VER.*"

  local RM_CSHARP_FILE_PATHNAME="$2"
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
  local RM_GRADLE_FILE_PATHNAME="$1"

  cat "$RM_GRADLE_FILE_PATHNAME" | grep -E "^version" | eval "$MATCH \'.*\'" | sed "s/'//g"
}

setVersion_gradle() {
  local V=$1
  local RM_GRADLE_FILE_PATHNAME="$2"
  local FC="$(cat "$RM_GRADLE_FILE_PATHNAME")"

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
  local RM_GRADLE_KOTLIN_FILE_PATHNAME="$1"

  grep -E "^version" < "$RM_GRADLE_KOTLIN_FILE_PATHNAME" | grep -Eo "['\"].*['\"]" | tr '"' ' ' | tr "'" ' ' | xargs
}

# usage: setVersion version
setVersion_gradlekts() {
  local V=$1
  local RM_GRADLE_KOTLIN_FILE_PATHNAME="$2"
  local FC="$(cat "$RM_GRADLE_KOTLIN_FILE_PATHNAME")"

  echo "$FC" \
  | sed "s/^version.*/version = \"$V\"/" \
  > "$RM_GRADLE_KOTLIN_FILE_PATHNAME"

  verbose "$RM_GRADLE_KOTLIN_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_GRADLE_KOTLIN_FILE_PATHNAME")"
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
  local RM_DOCKER_FILE_PATHNAME="$1"

  echo "$(grep -E '^LABEL' "$RM_DOCKER_FILE_PATHNAME" | grep -Eo "$RM_DOCKER_VERSION_LABEL=\"?[0-9]+\.[0-9]+\.[0-9]+(-[^ \"]*)?\"?" | cut -d'=' -f2 | sed 's/"//g')"
}

setVersion_docker() {
  local V=$1
  local RM_DOCKER_FILE_PATHNAME="$2"
  local label
  local first=true
  local lines

  printf "$(cat "$RM_DOCKER_FILE_PATHNAME")\n" | while read line; do
    label="$(echo "$line"  | grep -E '^LABEL' | grep -E "$RM_DOCKER_VERSION_LABEL=\"?[0-9]+\.[0-9]+\.[0-9]+(-[^ \"]*)?\"?" || true)"
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
  verbose "$(cat "$RM_DOCKER_FILE_PATHNAME")"
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
  local RM_MAVEN_FILE_PATHNAME="$1"

  eval "$XMLSTARLET sel -N x=http://maven.apache.org/POM/4.0.0 -t -v /x:project/x:version -" < "$RM_MAVEN_FILE_PATHNAME"
}

setVersion_maven() {
  local V=$1
  local RM_MAVEN_FILE_PATHNAME="$2"

  eval "$XMLSTARLET ed -P -N x=http://maven.apache.org/POM/4.0.0 -u /x:project/x:version -v $V" > "$RM_MAVEN_FILE_PATHNAME.tmp" < "$RM_MAVEN_FILE_PATHNAME"
  mv "$RM_MAVEN_FILE_PATHNAME.tmp" "$RM_MAVEN_FILE_PATHNAME"

  verbose "$RM_MAVEN_FILE_PATHNAME is now:"
  verbose "$(cat "$RM_MAVEN_FILE_PATHNAME")"
}
#####
##### end Maven pom.xml support
#####

#####
##### begin nodejs package.json support
#####
RM_NODEJS_DIR="${RM_NODEJS_DIR:-$(pwd)}"

getVersion_nodejs() {
  local RM_NODEJS_DIR_PATHNAME="$1"
  RM_NODEJS_DIR_PATHNAME="$(realpath "$RM_NODEJS_DIR_PATHNAME")"

  local RM_NODEJS_DOCKER="docker run --rm -i -v $RM_NODEJS_DIR_PATHNAME:/cwd -w /cwd node"
  local RM_NODEJS_NODE=node
  if [ -n "$NO_USE_LOCAL_NODEJS" ] || ! eval "$RM_NODEJS_NODE --version" >/dev/null 2>&1; then
    RM_NODEJS_NODE="$RM_NODEJS_DOCKER node"
  fi

  eval "$RM_NODEJS_NODE -e 'console.log(require(\"./package.json\").version)'"
}

setVersion_nodejs() {
  local V=$1
  local RM_NODEJS_DIR_PATHNAME="$2"
  RM_NODEJS_DIR_PATHNAME="$(realpath "$RM_NODEJS_DIR_PATHNAME")"
  local RM_NODEJS_DOCKER="docker run --rm -i -v $RM_NODEJS_DIR_PATHNAME:/cwd -w /cwd node"

  RM_NODEJS_NPM=npm
  if [ -n "$NO_USE_LOCAL_NPM" ] || ! eval "$RM_NODEJS_NPM --version" >/dev/null 2>&1; then
    RM_NODEJS_NPM="$RM_NODEJS_DOCKER npm"
  fi

  (cd "$RM_NODEJS_DIR_PATHNAME" && eval "$RM_NODEJS_NPM version --no-git-tag-version --allow-same-version $V")

  verbose "$RM_NODEJS_DIR_PATHNAME/package.json is now:"
  verbose "$(cat "$RM_NODEJS_DIR_PATHNAME/package.json")"
}
#####
##### end nodejs package.json support
#####

#####
##### begin Scala SBT support
#####
RM_SCALA_SBT_DIR="${RM_SCALA_SBT_DIR:-$(pwd)}"
RM_SCALA_SBT_FILE="${RM_SCALA_SBT_FILE:-build.sbt}"

getVersion_scala() {
  local RM_SCALA_SBT_FILE_PATHNAME="$1"

  grep -E '^\s*version\s*:=\s*".*"\s*$' < "$RM_SCALA_SBT_FILE_PATHNAME" | eval "$MATCH '(\d+\.\d+\.\d+(-.+\.\d+)?)'" | awk '{ print $1 }'
}

setVersion_scala() {
  local V=$1
  local RM_SCALA_SBT_FILE_PATHNAME="$2"
  local FC="$(cat "$RM_SCALA_SBT_FILE_PATHNAME")"

  echo "$FC" \
  | sed -E "s/^\s*version *:= *\".+\" *$/version := \"$V\"/" \
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
  local RM_VERSION_FILE_PATHNAME="$1"

  xargs < "$RM_VERSION_FILE_PATHNAME"
}

setVersion_version() {
  local V=$1
  local RM_VERSION_FILE_PATHNAME="$2"

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
  where options are as follows:\n \
  --tech|-t                                 # required or implied by other arguments at least once, the technology types to release (comma-delimited list ok); choose from:\n \
                                            #  'helm' for Helm Chart (Chart.yaml),\n \
                                            #  'docker' for Docker Image (Dockerfile),\n \
                                            #  'nodejs' for Node.js (package.json),\n \
                                            #  'csharp' for C# (AssemblyInformationalVersion in AssemblyInfo.cs),\n \
                                            #  'scala' for Scala (build.sbt),\n \
                                            #  'gradle' for Gradle (build.gradle),\n \
                                            #  'gradlekts' for Kotlin Gradle (build.gradle.kts),\n \
                                            #  'maven' for Maven XML (pom.xml),\n \
                                            #  'version' for plain text version file (VERSION),\n \
  [--origin|-o origin]                      # optional, git origin, default '%s' (if given multiple times, last one wins)\n \
  [--main|-m main]                          # optional, git main branch, default '%s' (if given multiple times, last one wins)\n \
  [--cherry-pick-to-main]                   # optional, cherry pick first RC release commit to main branch, default true (if given multiple times, last one wins)\n \
  [--no-cherry-pick-to-main]                # optional, don't cherry pick first RC release commit to main branch, default false (if given multiple times, last one wins)\n \
  [--release-tag-prefix|-p prefix]          # optional, git release tag prefix, default '%s' (if given multiple times, last one wins)\n \
  [--release-tag-suffix|-s suffix]          # optional, git release tag suffix, default  '%s' (if given multiple times, last one wins)\n \
  [--release-branch-prefix|-P prefix]       # optional, git release branch prefix, default '%s' (if given multiple times, last one wins)\n \
  [--release-branch-suffix|-S suffix]       # optional, git release branch suffix, default '%s' (if given multiple times, last one wins)\n \
  [--git-commit-opts|-o opts]               # optional, git commit options ('--no-verify' is common), default '%s' (if given multiple times, last one wins)\n \
  [--git-push-opts|-O opts]                 # optional, git push options ('--no-verify' is common), default '%s' (if given multiple times, last one wins)\n \
  [--pre-release-token|-k token]            # optional, pre release token, default '%s' (if given multiple times, last one wins)\n \
  [--rc-release-token|-K token]             # optional, release candidate release token, default '%s' (if given multiple times, last one wins)\n \
  [--dev-qa]                                # optional, shortcut for '--main dev --pre-release-token dev --rc-release-token qa' (if other shortcut options given multiple times, last one wins)\n \
  [--trunk-qa]                              # optional, shortcut for '--main trunk --pre-release-token trunk --rc-release-token qa' (if other shortcut options given multiple times, last one wins)\n \
  [--alpha-beta]                            # optional, shortcut for '--main alpha --pre-release-token alpha --rc-release-token beta' (if other shortcut options given multiple times, last one wins)\n \
  [--pre-rc]                                # optional, shortcut for legacy behavior of '--main master --pre-release-token pre --rc-release-token rc' (if other shortcut options given multiple times, last one wins)\n \
  [--helm-chart-dir chartDir]               # optional, chart directory (option allowed multiple times) or colon-separated pathnames to chart directories, if given implies '--tech helm', default cwd ('%s')\n \
  [--csharp-file csharpFile]                # optional, csharp filename (option allowed multiple times) or colon-separated pathnames to csharp filenames, if given implies '--tech csharp', default '%s'\n \
  [--gradle-file gradleFile]                # optional, gradle filename (option allowed multiple times) or colon-separated pathnames to gradle filenames, if given implies '--tech gradle', default '%s'\n \
  [--gradlekts-file gradlektsFile]          # optional, gradlekts filename (option allowed multiple times) or colon-separated pathnames to gradlekts filenames, if given implies '--tech gradlekts', default '%s'\n \
  [--docker-file dockerFile]                # optional, docker filename (option allowed multiple times) or colon-separated pathnames to docker filenames, if given implies '--tech docker', default '%s'\n \
  [--docker-file-version-label label]       # optional, docker file version label, if given implies '--tech docker', default '%s'\n \
  [--maven-file mavenFile]                  # optional, maven POM filename (option allowed multiple times) or colon-separated pathnames to maven POM filenames, if given implies '--tech maven', default '%s'\n \
  [--nodejs-dir nodejsDir]                  # optional, nodejs project directory (option allowed multiple times) or colon-separated pathnames to nodejs project directories, if given implies '--tech nodejs', default '%s'\n \
  [--scala-file buildSbt]                   # optional, scala SBT filename (option allowed multiple times) or colon-separated pathnames to scala SBT filenames, if given implies '--tech scala', default '%s'\n \
  [--version-file versionFile]              # optional, VERSION file filename (option allowed multiple times) or colon-separated pathnames to VERSION file filenames, if given implies '--tech version', default '%s'\n \
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
    "$RM_CSHARP_DIR/$RM_CSHARP_FILE" \
    "$RM_GRADLE_DIR/$RM_GRADLE_FILE" \
    "$RM_GRADLE_KOTLIN_DIR/$RM_GRADLE_KOTLIN_FILE" \
    "$RM_DOCKER_DIR/$RM_DOCKER_FILE" \
    "$RM_DOCKER_VERSION_LABEL" \
    "$RM_MAVEN_DIR/$RM_MAVEN_FILE" \
    "$RM_NODEJS_DIR" \
    "$RM_SCALA_DIR/$RM_SCALA_FILE" \
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
    RM_PATHNAMES_helm=":$RM_PATHNAMES_helm:$1"
    shift
    RM_TECH="$RM_TECH,helm"
    ;;
  --helm-chart-file) # deprecated because filename "Chart.yaml" is not configurable in node.js
    shift
    RM_HELM_CHART_FILE="$1"
    shift
    RM_HELM_CHART_FILE="$(realpath "$(dirname "$RM_HELM_CHART_FILE")")"
    echo "WARN: option --helm-chart-file is deprecated because filename 'Chart.yaml' is not configurable; assuming '--helm-chart-dir $RM_HELM_CHART_FILE' instead" >&2
    RM_PATHNAMES_helm=":$RM_PATHNAMES_helm:$RM_HELM_CHART_FILE:"
    RM_TECH="$RM_TECH,helm"
    ;;
  --csharp-file)
    shift
    RM_PATHNAMES_csharp=":$RM_PATHNAMES_csharp:$1:"
    shift
    RM_TECH="$RM_TECH,csharp"
    ;;
  --gradle-file)
    shift
    RM_PATHNAMES_gradle="$RM_PATHNAMES_gradle:$1:"
    shift
    RM_TECH="$RM_TECH,gradle"
    ;;
  --gradlekts-file)
    shift
    RM_PATHNAMES_gradlekts="$RM_PATHNAMES_gradlekts:$1:"
    shift
    RM_TECH="$RM_TECH,gradlekts"
    ;;
  --docker-file)
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
    RM_PATHNAMES_maven=":$RM_PATHNAMES_maven:$1:"
    shift
    RM_TECH="$RM_TECH,maven"
    ;;
  --scala-file)
    shift
    RM_PATHNAMES_scala=":$RM_PATHNAMES_scala:$1:"
    shift
    RM_TECH="$RM_TECH,scala"
    ;;
  --nodejs-file) # deprecated because filename "package.json" is not configurable in node.js
    shift
    RM_NODEJS_FILE="$1"
    shift
    RM_NODEJS_FILE="$(realpath "$(dirname "$RM_NODEJS_FILE")")"
    echo "WARN: option --nodejs-file is deprecated because filename 'package.json' is not configurable; assuming '--nodejs-dir $RM_NODEJS_FILE' instead" >&2
    RM_PATHNAMES_nodejs=":$RM_PATHNAMES_nodejs:$RM_NODEJS_FILE:"
    ;;
  --nodejs-dir)
    shift
    RM_PATHNAMES_nodejs=":$RM_PATHNAMES_nodejs:$1:"
    shift
    RM_TECH="$RM_TECH,nodejs"
    ;;
  --version-file)
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

# ensure at least one tech given
RM_TECHNOLOGIES="$(echo -n "$RM_TECH" | tr ',' '\n' | uniq | xargs)"
if [ -z "$RM_TECHNOLOGIES" ]; then
  echo "ERROR: no technologies given or implied" >&2
  usage >&2
  exit $RM_ERR_INVOCATION
fi

# default things if necessary
if [ -z "$RM_PATHNAMES_helm" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)helm(\s+|$)'; then
  RM_PATHNAMES_helm="$(realpath "$RM_HELM_CHART_DIR/$RM_HELM_CHART_FILE")"
fi
if [ -z "$RM_PATHNAMES_csharp" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)csharp(\s+|$)'; then
  RM_PATHNAMES_csharp="$(realpath "$RM_CSHARP_DIR/$RM_CSHARP_FILE")"
fi
if [ -z "$RM_PATHNAMES_gradle" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)gradle(\s+|$)'; then
  RM_PATHNAMES_gradle="$(realpath "$RM_GRADLE_DIR/$RM_GRADLE_FILE")"
fi
if [ -z "$RM_PATHNAMES_gradlekts" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)gradlekts(\s+|$)'; then
  RM_PATHNAMES_gradlekts="$(realpath "$RM_GRADLE_KOTLIN_DIR/$RM_GRADLE_KOTLIN_FILE")"
fi
if [ -z "$RM_PATHNAMES_docker" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)docker(\s+|$)'; then
  RM_PATHNAMES_docker="$(realpath "$RM_DOCKER_DIR/$RM_DOCKER_FILE")"
fi
if [ -z "$RM_PATHNAMES_maven" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)maven(\s+|$)'; then
  RM_PATHNAMES_maven="$(realpath "$RM_MAVEN_DIR/$RM_MAVEN_FILE")"
fi
if [ -z "$RM_PATHNAMES_scala" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)scala(\s+|$)'; then
  RM_PATHNAMES_scala="$(realpath "$RM_SCALA_SBT_DIR/$RM_SCALA_SBT_FILE")"
fi
if [ -z "$RM_PATHNAMES_nodejs" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)nodejs(\s+|$)'; then
  RM_PATHNAMES_nodejs="$(realpath "$RM_NODEJS_DIR")"
fi
if [ -z "$RM_PATHNAMES_version" ] && echo "$RM_TECHNOLOGIES" | grep -Eq '(^|\s+)version(\s+|$)'; then
  RM_PATHNAMES_version="$(realpath "$RM_VERSION_DIR/$RM_VERSION_FILE")"
fi

# validations

uniquifyPaths() {
  echo "$1" | tr ':' '\n' | uniq | tr '\n' ':' | sed -E 's/:{2,}/:/g' | sed -E 's/^://' | sed -E 's/:$//'
}

for t in $RM_TECHNOLOGIES; do
  UP="$(eval "echo \$RM_PATHNAMES_$t")"
  UP="$(uniquifyPaths "$UP")"
  eval "RM_PATHNAMES_$t='$UP'"
  verbose "INFO: $t paths=$(eval "echo \$RM_PATHNAMES_$t")"
done

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
    local pathnames="$(eval "echo \$RM_PATHNAMES_$t")"
    ORIG_IFS="$IFS"
    export IFS=':'
    for p in $pathnames; do
      setVersion_$t $1 "$p"
    done
    export IFS="$ORIG_IFS"
  done
}

verbose "INFO: invocation ok; checking required preconditions"

git pull $RM_ORIGIN

verbose "checking that all versions are exactly the same"
for t in $RM_TECHNOLOGIES; do
  pathnames="$(eval "echo \$RM_PATHNAMES_$t")"
  ORIG_IFS="$IFS"
  export IFS=':'
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
  export IFS="$ORIG_IFS"
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

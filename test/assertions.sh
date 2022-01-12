#!/usr/bin/env bash
set -e

export YMLX="docker run --rm -i matthewadams12/ymlx"
export XMLSTARLET="docker run --rm -i jakubsacha/docker-xmlstarlet"

getVersion_helm() {
  local RM_HELM_CHART_DIR_PATHNAME="$1"

  eval "$YMLX this.version" < "$RM_HELM_CHART_DIR_PATHNAME/Chart.yaml"
}
getVersion_csharp() {
  local RM_CSHARP_FILE_PATHNAME="$1"

  cat "$RM_CSHARP_FILE_PATHNAME" | grep -E "$RM_CSHARP_ENTRY" | eval "$MATCH '(\d+\.\d+\.\d+(-.+\.\d+)?)'" | awk '{ print $1 }'
}
getVersion_gradle() {
  local RM_GRADLE_FILE_PATHNAME="$1"

  cat "$RM_GRADLE_FILE_PATHNAME" | grep -E "^version" | eval "$MATCH \'.*\'" | sed "s/'//g"
}
getVersion_gradlekts() {
  local RM_GRADLE_KOTLIN_FILE_PATHNAME="$1"

  grep -E "^version" < "$RM_GRADLE_KOTLIN_FILE_PATHNAME" | grep -Eo "['\"].*['\"]" | tr '"' ' ' | tr "'" ' ' | xargs
}
getVersion_docker() {
  local RM_DOCKER_FILE_PATHNAME="$1"

  echo "$(grep -E '^LABEL' "$RM_DOCKER_FILE_PATHNAME" | grep -Eo "$RM_DOCKER_VERSION_LABEL=\"?[0-9]+\.[0-9]+\.[0-9]+(-[^ \"]*)?\"?" | cut -d'=' -f2 | sed 's/"//g')"
}
getVersion_maven() {
  local RM_MAVEN_FILE_PATHNAME="$1"

  eval "$XMLSTARLET sel -N x=http://maven.apache.org/POM/4.0.0 -t -v /x:project/x:version -" < "$RM_MAVEN_FILE_PATHNAME"
}
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
getVersion_scala() {
  local RM_SCALA_SBT_FILE_PATHNAME="$1"

  grep -E '^\s*version\s*:=\s*".*"\s*$' < "$RM_SCALA_SBT_FILE_PATHNAME" | eval "$MATCH '(\d+\.\d+\.\d+(-.+\.\d+)?)'" | awk '{ print $1 }'
}
getVersion_version() {
  local RM_VERSION_FILE_PATHNAME="$1"

  xargs < "$RM_VERSION_FILE_PATHNAME"
}

assertVersion() {
  local actual="$(eval "getVersion_$1 $2")"
  if [ "$actual" != "$3" ]; then
    echo "ASSERTION FAILURE: expected version '$3'; actual was '$actual'" >&2
    exit 1
  fi
}

assertBranch() {
  local actual="$(git branch --show-current)"
  if [ "$actual" != "$1" ]; then
    echo "ASSERTION FAILURE: expected current branch '$1'; actual was '$actual'" >&2
    exit 1
  fi
}

# usage:
# assertGitLog 2 message 'foobar$' => assert that the message of the 2nd most recent line (1-based) matches regex 'foobar$'
assertGitLog() {
  local log="$(git log --pretty=format:%D#%s)"

  local n="$(echo $1 | grep -Eo '\d+$')"
  if [ -z "$n" ]; then
     echo "INVALID ASSERTION: no line number given" >&2
     exit 2
  else
    n=-$n
  fi
  local line="$(echo "$log" | head $n | tail -1)"

  local fail=''
  case $2 in
    message)
      if ! echo "$line" | cut -d '#' -f 2 | grep -Eq "$3"; then
        fail=1
      fi
      ;;
    tag)
      local rx="tag\:\s+$3"
      if ! echo "$line" | cut -d '#' -f 1 | grep -Eq "$rx"; then
        fail=1
      fi
      ;;
    *)
      echo "INVALID ASSERTION: only 'message' or 'tag' supported; got '$2'" >&2
      exit 2
      ;;
  esac
  if [ -n "$fail" ]; then
    echo "ASSERTION FAILURE: expected '$2' to match '$3' in line $n: '$line'" >&2
    exit 1
  fi
}

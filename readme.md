# Release Management Scripts

This repository contains a Bash shell script, `release.sh`, that assists in implementing a release management strategy
that is based on one release branch per minor version. Docker is currently a requirement, too.

In this strategy, the main branch (`main`, by default) contains the latest & greatest code, and branches are created for
each minor version (`vx.y`, for example `v2.4`), including all of its patches.

> NOTE: The version number at rest in your repository is _almost always_ at a prerelease level, except for the short amount of time during releases where prerelease suffixes are dropped and release commits and tags are created.

## Breaking changes prior to 2.x

There are breaking changes since versions prior to 2.x. To migrate from `release-management` _prior_ to version 2.x, see
the [migration guide](migrating-from-pre-2.x.md).

## Overview of the minor-release-per-branch strategy

This is a minor-release-per-branch strategy, and all that the script does is

* manipulate version strings,
* create release commits & tags, *
* create release branches, and
* push ot the git remote

so that your CI/CD process can actually perform releases based on branch & tag names as commits are pushed to your git
remotes. It does this in a low-tech manner, by using text processing tools (`sed`, `awk` & the usual suspects) to
manipulate files containing version strings.

### Prerequisites

These are the current prerequisites:

* `git` configured properly for local operation and access to any git remotes,
* `bash` (until we update to be portable across more shells),
* `docker`, so that you don't have to install tools that we depend on, and
* whichever technology-specific utilities (`node`, `npm`, `gradle`, etc) that you depend on.

### Supported project technologies

We currently support release management for various technologies:

* Helm charts
* Docker images using `Dockerfile`'s `LABEL` directive with a `version=` label
* Node.js projects using `npm` along with `package.json` (`yarn` is a TODO)
* Projects that use a plain-text `VERSION` file (by any name)
* .NET projects in C# that use an `AssemblyInfo.cs` file
* Maven projects that use a `pom.xml` file
* Gradle projects that use a `build.gradle` file
* Kotlin Gradle projects that use a `build.gradle.kts` file
* Scala projects that use a `build.sbt` file

If you need to support other project types, see below for developer information.

* The only supported source control system is [git](https://git-scm.com/).
* Version numbers are based on [Semantic Versioning](https://semver.org).
* The main branch, `main` by default, is assumed to always contain the latest & greatest _completed_ features and should
  be releasable at any time. Features _still in progress_ should be developed in feature branches. The name of this
  branch is configurable via the `--main` option, and _must_ sort alphabetically before your release candidate suffix.
* The default prerelease suffix in the main branch is the same as the main branch name (ie, `1.0.0-main.0`), and is
  configurable by setting the `--pre-release-token` option.
* The default prerelease suffix in release branches is `rc` for "release candidate" (ie, `1.0.0-rc.0`), and is
  configurable via the `--rc-release-token` option. This value _must_ sort alphabetically after the value of
  the `--pre-release-token` option.
* The name of the git remote is assumed to be `origin`, but is configurable via the `--origin` option.

## Note about deployables

It's convenient to align the names of your deployment environments with your branches & prerelease suffixes as much as
possible. For example, if you have a development cloud environment called `dev` that you deploy to continuously, you
should use `dev` for your main branch name & `dev` for your pre release token. Next, if you have a QA test envronment
that you deploy to for testing completed features as part of a release train, you should use `qa` for your RC release
token. This way, it is clear which prereleases of components & deployables should go into which environments.

There are some convenient preset options supported by the `release.sh` script:

* `--dev-qa`:  uses
    * `dev` for both the main branch name & pre prerelease token, and
    * `qa` for the RC prerelease token
* `--trunk-qa`:  uses
    * `trunk` for both the main branch name & pre prerelease token, and
    * `qa` for the RC prerelease token
* `--alpha-beta`:  uses
    * `alpha` for both the main branch name & pre prerelease token, and
    * `beta` for the RC prerelease token
* `--pre-rc`:  (closest to pre-2.x behavior) uses
    * `master` for the main branch name,
    * `pre` for pre prerelease token, and
    * `rc` for the RC prerelease token

## Helpful features

### _Your_ `release` script

Since you will likely customize your release management process, git repos & environments, we have provided a
basic [release.example](release.example) script for you to include in the repos that you use `release-management` in.
One convenient thing it does is to automatically download the version of [`release.sh`](release.sh) that you depend on,
so you should make sure to gitignore `release.sh` (plus, it would dork with your actual release if you didn't gitignore
it).

Copy [release.example](release.example) to your local repo, make it executable (`chmod +x ...` or similar), and modify
it to suit your needs. You should commit your copy of [release.example](release.example) along with the rest of your
repo contents.

### CI/CD integration

Git branches, semver strings and environments are all closely related. To illustrate, this repo includes examples based
on GitLab's CI/CD configuration file that illustrate how semver version strings are used to build, push artifacts &
deploy to different environments. Similar concepts apply to other CI/CD providers.

See [this minimal GitLab example file](.gitlab-ci.example-minimal.yml)
or [this GitLab & GCP/GCR/GKE example](.gitlab-ci.example-gcp.yml) for more information.

## Workflow

There are basically two key events while preparing for a release:

* Deciding that you're feature complete for the next release.
* Deciding that you're bug-free enough to release.

The following is a detailed description of the workflow.

> NOTE: In the following description, we'll assume a Node.js project that produces a built server-side application, a Docker image & a Helm chart containing the application that's ready for deployment. We'll also use `dev` for the main branch name and development prerelease suffix, and we'll use `qa` for our release candidate prerelease suffix.

* Create your codebase & place it under source control with `git` with a main/default branch name of `dev`.
* Set your version to its initial value in the main branch.
    * For brand new projects, we recommend starting with `0.1.0-dev.0`.
    * For existing projects, start with a minor version greater than the last minor version, like `0.2.0-dev.0` or
      whatever you need.
    * _New features should be developed in feature branches off of the main branch and only merged back to the main
      branch when they're considered complete._
* When you're ready to do your first development preview release, prerelease from your main branch with the
  command `./release.sh --tech nodejs,docker,helm --dev--qa dev`.
    * This will create tags & commits for your `dev` prerelease & push them, whereupon your CI/CD pipeline should kick
      in and actually perform your release workflow. This is dependent on your CI/CD provider and is left to you.
* When you've decided that you're _feature complete_, but not necessarily _bug-free_, you can create your next minor
  release branch with an initial release candidate from the main branch
  with `./release.sh --tech nodejs,docker,helm --dev--qa qa`.
    * This will create a release branch in the format `vx.y` where `x` is your main branch's current major version
      and `y` is its minor version. The initial version in the `vx.y` branch will be `x.y.0-qa.0`, which will be
      released, then it will be immediately bumped to `x.y.0-qa.1` in preparation for your next release candidate.
    * _Important:  Only bug fixes (AKA "patches") should ever be committed in release branches._
    * As you fix bugs in your release branch that arise from QA testing, make sure to assess whether they need to be
      backported to your main branch, which will almost always be true.
      `git cherry-pick -x` is a simple command with which to do that and works most of the time. Make sure to check
      its [documentation](https://git-scm.com/docs/git-cherry-pick).
* When you've decided that you're _sufficiently bug-free_ in your minor release branch to release to staging and/or
  production (often called a "GA", or "generally available" release), as agreed upon by your stakeholders (the
  development team, QA team, customers, customer advocates, etc), you can perform a minor release in that branch
  with `./release.sh --tech nodejs,docker,helm --dev--qa minor`.
    * This will result in a release commit with tag `vx.y.0`, and the script will bump your prerelease number in the
      release branch to `x.y.1-qa.0`, where `x` & `y` are your major & minor version numbers, respectively.
    * You can then indefinitely fix bugs & release patched release candidates
      via `./release.sh --tech nodejs,docker,helm --dev--qa qa` or release patched GA (general availability) releases
      via `./release.sh --tech nodejs,docker,helm --dev--qa patch`.
* In parallel after you've cut a minor release branch, you can continue doing work in `master` for your next minor
  release, `vx.z` where `z` is `y + 1`.

See also the [release workflow diagram](release-workflow.jpg) ([pdf](release-workflow.pdf)) or
its [Apple Keynote](https://www.apple.com/keynote/) [source](release-workflow.key).

### Monorepo support

Prior to version 2.1.0, this tool did not support monorepos. From 2.1.0 onward, it does.

In a monorepo, all version strings in all files containing versions must be _exactly_ the same.

> Supporting differing versions in the same monorepo would break the minor-release-per-branch workflow.

To use this tool with a monorepo, simply list all project files that need to be updated, except for
Node.js `package.json` files or Helm Chart `Chart.yaml` files, because neither `package.json` nor `Chart.yaml` are
configurable. For Node.js & Helm Chart projects, give the directory in which the project files can be found.

For example, in a monorepo with, say, a Java backend built with Maven in directory `backend` & an SPA frontend built
with Node.js in directory `frontend` of off the root of the git repo, use something like

```shell
$ ./release --dev-qa --maven-file backend/pom.xml --nodejs-dir frontend
```

You can specify project file/dir options multiple times, or provide colon-separated lists of project files/dirs.

Make sure you review the output of `./release.sh --help`.

### Prerequisites to running on Windows

* Project requires Hyper-v, Docker and WSL (Windows Subsystem for Linux).
* Hyper-v can be added to Windows through Control Panel -> Programs and Features -> Turn Windows features on or off. If
  Hyper-v isn't an option you may need to upgrade your version of Windows.
* Install Docker for Windows and choose the option of using Windows containers (default is linux). After docker is
  installed check the box in Settings -> General -> Expose daemon on tcp://localhost:2375 without TSL.
* To install WSL open a powershell as admin and
  type `Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux`.
* After WSL is installed use the Windows Store to install a distro of linux (Ubuntu recommend). If not installing Ubuntu
  you will need to adjust the url to get the PGP Key below.
* After your distro is installed open bash and run the following commands:
    * `sudo apt-get update -y`
    * `sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common`
    * `curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -`
    * `sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"`
    * `sudo apt-get update -y`
    * `sudo apt-get install -y docker-ce`
    * `sudo usermod -aG docker $USER`
    * `sudo apt-get install -y docker-compose`
    * `sudo mkdir /c` adjust for your drive where docker is installed. ignore if directory already exists.
    * `sudo mount --bind /mnt/c /c`
* Lastly, check that everything is running correctly.
    * `docker info`
    * `docker-compose --version`

## For contributors

### Releasing this repo

* This project Eats Its Own Dog Food™. It uses a plain text `VERSION` file to store its version. Use the
  script `./release`. It uses the preset `--dev-qa` as of this writing.
* `release.sh` implements the release workflow, but needs `getVersion_xxx` & `setVersion_xxx` functions for eah
  particular technology. They are all located in the `release.sh` file.
* In order to prevent a conflict with this repo's `release.sh` file, the `release` script downloads `release.sh`
  as `release.sh.this`.

### Testing

* Tests are in `test/`
    * Run `test/polyrepos/test-all.sh` to test the behavior against individual, polyrepo-style git repos.
    * Run `test/monorepo/test.sh` to test against a monorepo that has every technology supported by this tool.
    * There needs to be (more) assertions in the tests, and we need better saddy path coverage.
* To add a technology, copy & paste an existing one:
    * Copy an existing technology-specific section in `release.sh` (near the top) & massage to fit the new technology.
    * Update `test/polyrepos/**/*` to add your new type to those tested.
    * Update `test/monorepo/**/*` to add your new type to the monorepo under test.

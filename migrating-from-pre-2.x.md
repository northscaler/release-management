# Migrating from pre-2.x `release-management`

> NOTE: The behavior of `release-management` has not changed, only the syntax of the invocations.

Here are the steps to migrate from pre-2.x versions of `release-management`:

* Remove all legacy release scripts:  `rm release*` or similar.
* Update your `.gitignore` file if necessary so that you're ignoring `release.sh`.
* Download [the new `release.sh` script](release.sh) manually once.
* Make `release.sh` executable with `chmod +x release.sh` or similar.
* Understand its usage with `./release.sh --help`.
* Update your custom release script (usually called `rel`) to invoke `./release.sh` instead of `./release` with the
  proper options.
    * If your repo uses `master` for the main branch, and you use `pre` & `rc` for your pre & RC release tokens,
      respectively, you can simply use the `--pre-rc` option, which is a shortcut
      for `--main master --pre-release-token pre --rc-release-token rc`.
    * If your repo uses `dev` for the main branch, and you use `dev` & `qa` for your pre & RC release tokens,
      respectively, you can simply use the `--dev-qa` option, which is a shortcut
      for `--main dev --pre-release-token dev --rc-release-token qa`.
    * Identify the new names of the technologies that you're using and pass them in the `--tech` option.

For example, if your invocation used to be

```shell
# in your custom `rel` script
MASTER=dev PRE=dev RC=qa ./release nodejs+image+chart $@
```

then the new invocation would be

```shell
# in your custom `rel` script
./release.sh --dev-qa --tech nodejs,docker,helm $@
```

Remember, `./release.sh --help` is your friend.

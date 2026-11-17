# setup-runtime-resource

Concourse resource (`solureal/setup-runtime-resource`) that builds a Wolfi (glibc, apk) rootfs at pipeline time, cached
by Concourse. The image is Wolfi too and bakes a base rootfs (`apk add --root`; see the Dockerfile) as `base.tar.zst`;
`in` extracts it, upgrades and installs `dependencies` with the host's `apk --root`, then deletes apk. `check` = SHA-256 of `source`;
`in` builds; `out` no-op.

## Tests

E2E only, against the local Concourse stack in `docker-compose.yml` (web :8080, registry :5000, git-server):

```bash
./build-and-test.sh                  # all
TEST="maven gradle" ./build-and-test.sh
```

- A **test** covers one runtime or feature: `test/resources/<name>/{source.yml,test.sh}` and an optional `test.env`
  (names sort so `java` and `java-rc` sit together). All jobs run the one task `test/resources/task.yml` with
  `TEST: <name>`; `run.sh` prints the `>>> TEST TASK START <<<` marker, defines `assert_contains` /
  `assert_not_contains` and **sources** `<name>/test.sh` (so BASH_ENV's nvm/sdk/caches are live). Sample projects
  are in `test/resources/projects/`; `test.sh` gets `$PROJECTS`. `example/pipeline.yml` is a user sample, not a test.
- Adding a test = adding its directory; nothing else. `test/pipeline.sh` (bash + mikefarah yq v4) prints a base pipeline
  (`ci/pipeline.yml`, `test/pipeline.yml`) plus a resource and `test-<name>` job per test, and `test-full`: every
  test's `test.sh` as one `in_parallel` step against one image whose source is the deep merge of all `source.yml`s
  (lists unioned, different scalars fail naming both tests, so pin ONE version per tool across tests). Steps are
  `privileged` when their image enables testcontainers. The deploy and `build-and-test.sh` set the rendered pipeline, never the base file.
- `ci/tasks/run-tests.sh` (the `test` job, on the resource image itself) clears each step's task cache, triggers
  each `test-<name>` job twice (`PARALLEL` jobs at once, default 4) and checks the **second** (warm) run: no
  `Download`/`Pulling` after the marker unless `test.env` sets `DOWNLOADS_ON_WARM_RUN="<why>"`, and one
  `[cache] restore <key> from=local <unit>=N` per key in `test.env`'s `RESTORES_CACHE_DIRECTORIES`. `full` checks the
  union of all keys and skips the download check.
- Locally `test/pipeline.sh --no-rootless` sets `rootless: false` (no user namespaces, so dockerd);
  `testcontainers/test.sh` runs its rootless-only checks when
  `TESTCONTAINERS_ROOTLESS=true`.
- Always assert a positive event (a `RESTORES_CACHE_DIRECTORIES` key such as `gradle/modules-2`), never an absence;
  silence passes for a run that did nothing.
- A cache logs only what it moved. Never emit zero events (`from=none`, `files=0`, `status=unchanged`).

## Architecture

Per runtime: `assets/installers/<name>.sh` (host: `<name>_get_dependencies`, `<name>_install`, wired into
`assets/in`), `assets/runtimes/<name>.sh` (installs inside the chroot), `assets/includes/<name>.sh`
(sourced from `bashrc.sh` at task time; registers caches). Also document new `source` options in `README.md`.

`in` runs apk from the resource host (no fakechroot: it is unmaintained; tasks have CAP_SYS_CHROOT and CAP_MKNOD but no
user namespaces) and the `hook` in a plain `chroot`. A chroot has no /dev or /proc and can't mount them, so `in` mknods
a few /dev nodes for the build and removes them at the end. The runtime installers run on the host against the rootfs
path, so they need neither. `hooks/customize-*.sh` run once apk is deleted; `in` rewrites absolute symlinks at the end.
The resource image must be Wolfi, since runtime installers run rootfs binaries on the host (glibc, libstdc++).
Package names in `installers/*.sh` are Wolfi's (check with `apk search -x`); Wolfi has no
`passt` or `podman-docker`, so rootless testcontainers use slirp4netns and a `docker` link to podman.

`hooks/customize-10-runtimes.sh` runs the runtime scripts as concurrent groups (`sdkman java`, `nvm node`, `python`,
`golang`; add new runtimes there) and fails the build with the failing group's output. Per group (`$GROUP_NAME`),
`info_spinner` logs one atomic `▶`/`✔` line per step to the shared `$OUTPUT_FILE` (no `\r` spinners), raw tool output goes
to a private file shown only on failure or `verbose`, and `$RUNTIME_BASHRC` is merged afterwards in fixed order. Write `.bashrc` lines to `$RUNTIME_BASHRC`, never the rootfs file. Installs inside a group stay
serial: sdkman's shared state is not safe for concurrent `sdk install`.

Caching invariants:
- Everything is cached **in place**: a tool pointed at `$CACHE_DIRECTORY` by an env var and registered with
  `register_cache_dir <key> <dir>`. No archives, copies or symlinks (both were tried and removed).
  If a tool can't be pointed there, it isn't cached.
- The registry in `bashrc.sh` stays empty; each plugin registers its own keys at source time.
- sdkman/nvm/uv/corepack versions are baked into the rootfs, not cached. Installs a task runs itself
  (`.nvmrc`, `.sdkmanrc`) extract again every build. Only nvm's archive (`node/nvm`, via an overridden
  `nvm_cache_dir`) and uv's interpreter archives (`uv/python`) are cached: sdkman hardcodes `$SDKMAN_DIR/tmp`
  and always re-downloads, so java-rc keeps `DOWNLOADS_ON_WARM_RUN`.
- `create_m2_dir` writes settings.xml to both `~/.m2` and `$MAVEN_USER_HOME`; keep both.
- pnpm's store var is `npm_config_store_dir` (`PNPM_STORE_PATH` does nothing).
- The `hook` runs before `bashrc.sh` is appended to `.bashrc`, so no plugin (or cache) is active in it.

## CI (`ci/pipeline.yml`)

`build` → `test` (triggered by hand; runs every test and `full`; all of them gate the release) → `publish-major/minor/patch`.

PRs labelled `concourse` get their own pipeline (`ci/pr-pipeline.yml`, rendered by `test/pipeline.sh` and set by
`set-pr-pipelines`): it builds the `pr-<number>` image and runs the same `run-tests` task as master's `test` job against it.

Public repo: only `((var))` references, no literals, no vars file. The private deploy repo supplies the values and
sets the pipeline that `test/pipeline.sh ci/pipeline.yml` renders.

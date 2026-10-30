# setup-runtime-resource

Concourse resource (`solureal/setup-runtime-resource`) that builds a Debian trixie rootfs at pipeline time
with `mmdebstrap` + `fakechroot`, cached by Concourse. `check` = SHA-256 of `source`; `in` builds; `out` no-op.

## Tests

E2E only, against the local Concourse stack in `docker-compose.yml` (web :8080, registry :5000, git-server,
apt-cacher):

```bash
./build-and-test.sh                  # all
TEST="maven gradle" ./build-and-test.sh
```

- A test is a directory `example/tests/<name>/` (`source.yml`, `task.yml`, optional `test.env` with
  `EXPECT_IN_OUTPUT` / `FORBID_IN_OUTPUT` / `SKIP_CACHE_CHECK` / `FORCE_ROOTLESS`). Adding one also needs a
  resource + job in **both** `ci/pipeline.yml` and `example/pipeline.yml`. Tasks take the whole repo as input
  `repo` and must source `repo/$PROJECTS_DIR/tests/assert.sh` first.
- `ci/tasks/run-tests.sh` runs every job twice and asserts on the **second** (warm) run: no
  `Download`/`Pulling` after `>>> TEST TASK START <<<`, plus positive `[cache]` events.
- Always assert a positive event (`restore gradle/modules-2 from=local files=[1-9]`), never an absence;
  silence passes for a run that did nothing.
- A cache logs only what it moved. Never emit zero events (`from=none`, `files=0`, `status=unchanged`).

## Architecture

Per runtime: `assets/installers/<name>.sh` (host: `<name>_get_dependencies`, `<name>_install`, wired into
`assets/in`), `assets/hooks/customize-NN-<name>.sh` (installs inside the chroot), `assets/includes/<name>.sh`
(sourced from `bashrc.sh` at task time; registers caches). Also document new `source` options in `README.md`.

Caching invariants:
- Everything is cached **in place**: a tool pointed at `$CACHE_DIRECTORY` by an env var and registered with
  `register_cache_dir <key> <dir>`. No archives, copies or symlinks (both were tried and removed).
  If a tool can't be pointed there, it isn't cached.
- The registry in `bashrc.sh` stays empty; each plugin registers its own keys at source time.
- sdkman/nvm/pyenv/corepack versions are baked into the rootfs, not cached. Installs a task runs itself
  redo every build (hence `SKIP_CACHE_CHECK` in `rc-files` and `python`).
- `create_m2_dir` writes settings.xml to both `~/.m2` and `$MAVEN_USER_HOME`; keep both.
- pnpm's store var is `npm_config_store_dir` (`PNPM_STORE_PATH` does nothing).
- `assets/in` runs the build-time chroot with `ENABLE_CACHE=false`.

## CI (`ci/pipeline.yml`)

`build` → `test` (release gate over the `gating-tests` anchor) → `publish-major/minor/patch`.
`testcontainers-rootless` runs from `test-experimental` and must never gate a release.

Public repo: only `((var))` references, no literals, no vars file. The private deploy repo supplies values and globs `example/tests/` into
`SOURCE_<NAME>` vars.

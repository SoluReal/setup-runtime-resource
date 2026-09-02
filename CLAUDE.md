# CLAUDE.md

## What This Is

`setup-runtime-resource` is a [Concourse CI](https://concourse-ci.org/) resource that builds a lightweight Debian rootfs
at pipeline time using `mmdebstrap` + `fakechroot` — eliminating the need for teams to maintain custom Docker images and
a registry. The rootfs is cached by Concourse and reused across jobs.

The resource is published to Docker Hub as `solureal/setup-runtime-resource`.

## Running Tests

Tests run end-to-end against a local Concourse cluster via Docker Compose. There are no unit tests — correctness is
verified by actually running a Concourse pipeline.

```bash
# Start the local Concourse stack and run every test (requires fly CLI and Docker):
./build-and-test.sh

# One specific test, or a few:
TEST=maven ./build-and-test.sh
TEST="maven gradle" ./build-and-test.sh
```

`build-and-test.sh` only gets the stack ready and hands over:

1. Builds and pushes the resource image to the local registry (`localhost:5000`)
2. Recreates the git-server so the served repository matches the working tree
3. Sets `example/pipeline.yml` — one manually-triggered `test-<name>` job per test — and triggers its `test` job
4. That job runs `ci/tasks/run-tests.sh`, which is the same script CI's `test` job runs

### Every test runs twice

`ci/tasks/run-tests.sh` clears a test job's task cache, runs the job, then runs it again and makes its assertions
against the **second** run. That is the whole point: this resource exists to cache things, and a cold run only ever
proves that building from scratch works. Restoring is where the interesting failures are — a cache that was saved
under the wrong key, a partially restored directory, a file that came back without its executable bit.

It is also why every `test-<name>` job is manually triggered in both pipelines. Nothing but the `test` job (and
`test-experimental`, for the two that must not gate a release) is meant to start them.

After the second run it checks that the task logged no `Download`/`Pulling` — the split point being the
`>>> TEST TASK START <<<` line `example/tests/assert.sh` prints, so a rootfs rebuild on a fresh worker does not
count as a cache miss. Tests that legitimately fetch something on every run switch the check off in their
`test.env`, saying what and why.

That check can only ever prove a negative, and it passes just as happily for a run that did nothing at all — which
is exactly how an S3 tier that had disabled itself over an empty credential once produced two green runs. So the
second half of every cache assertion is positive, and matches the `[cache]` events the runtime emits (documented
under *Reading the cache log* in the README): each one names the tier a cache actually came from, so a `test.env`
can require `restore gradle/modules-2 from=local files=[1-9]` rather than infer it from silence. `EXPECT_IN_OUTPUT`
and `FORBID_IN_OUTPUT` hold one extended regex per line, all matched against the second run's build log.

When adding a cache to the runtime, **never log an event that reports zero of something**. A cache logs what it
moved: `restore` only when something came back, `save` only when something was written. No `from=none`, no
`status=unchanged`, no `files=0`. A build would otherwise open with a wall of lines each announcing nothing
happened, which reads like a fault rather than the normal cold start it is. Failures are the exception and are
always logged — `status=failed` means something broke, not that something was empty.

That makes silence ambiguous by design — a key with no line either had nothing cached or is not in play at all — so
a test asserts on the positive event (`restore gradle/modules-2 from=local files=[1-9]`) and never on the absence
of one. The single `tier s3=...` line is the exception that keeps this readable: it states once, up front, whether
the S3 tier is in play and why not, so no per-key line has to repeat it.

### Test Layout

Each test is a directory under `example/tests/`:

| File         | Role                                                                     |
|--------------|--------------------------------------------------------------------------|
| `source.yml` | The resource `source` — what runtime to build                            |
| `task.yml`   | The Concourse task config — what to assert once it is built              |
| `test.env`   | Optional per-test knobs: `EXPECT_IN_OUTPUT`, `FORBID_IN_OUTPUT`, `SKIP_CACHE_CHECK`, `FORCE_ROOTLESS` |

That directory is the single definition of a test, read by both pipelines, so what a contributor runs locally is
what CI runs. Adding a test means adding a directory, plus a resource and a job in **both** `ci/pipeline.yml` and
`example/pipeline.yml`; the deployment side needs no change, because it derives the `SOURCE_<NAME>` vars by
globbing this directory.

Two conventions make one task file work in both places:

- **`repo` input.** Every task declares it, and it is the whole repository either way — the local git-server serves
  `example/` and `ci/` at the paths CI's git resource has them.
- **`PROJECTS_DIR`.** `example` in both. Sample projects are reached as `repo/$PROJECTS_DIR/gradle`, and the shared
  assertion helpers as `repo/$PROJECTS_DIR/tests/assert.sh`, which every task must source first.

## Architecture

### Concourse Resource Protocol

The resource implements the three required Concourse scripts in `assets/`:

| Script  | Role                                                                             |
|---------|----------------------------------------------------------------------------------|
| `check` | Returns a version based on a SHA-256 hash of the `source` config                 |
| `in`    | Builds the rootfs (the heavy lifting) and writes it to the destination directory |
| `out`   | No-op; returns the passed-in version                                             |

The `check` script uses a content-addressed hash of the `source` config as the version — meaning the resource re-runs
only when the source configuration changes.

### `in` Script Flow

1. Parses `source` config from stdin JSON
2. Collects required Debian packages from installer modules (`installers/*.sh`)
3. Runs `mmdebstrap` to bootstrap a minimal Debian `trixie` rootfs into a tarball
4. Extracts the tarball to `$dest/rootfs/`
5. Runs `mmdebstrap` customize hooks (`hooks/customize-*.sh`) inside the chroot to install runtimes (SDKMAN, NVM, pyenv,
   Go, testcontainers/Docker)
6. Appends runtime init scripts to `/root/.bashrc` in the rootfs so they activate when a Concourse task runs
7. Writes `metadata.json` with environment variables Concourse should inject into the task

### Installer Modules

Each runtime is split across two layers:

- **`assets/installers/<name>.sh`** — called during `in`, runs on the host inside the resource container; declares what
  Debian packages are needed (`*_get_dependencies`) and may do host-side setup
- **`assets/hooks/customize-NN-<name>.sh`** — mmdebstrap customize hooks that run inside the new chroot to install the
  actual runtime (via curl/bash installers)
- **`assets/includes/<name>.sh`** — sourced into `/root/.bashrc` inside the rootfs at task runtime; handles cache
  restore/save and `sdk env`, `nvm use`, etc.

### Runtime Cache Pattern

At task startup, `assets/includes/bashrc.sh` is sourced. It:

- Sets package-manager cache dirs to `$CACHE_DIRECTORY` (a Concourse task cache volume)
- Runs `ON_INITIALIZE_CALLBACKS` (registered by each `includes/*.sh` to restore caches)
- Runs `TEARDOWN_CALLBACKS` on `EXIT` trap (registered by each `includes/*.sh` to save caches)

Everything is cached **in place**: nothing is ever compressed into an archive, so no build pays a
compress-and-extract of its own dependency tree. Two ways of getting there:

- **Pointed at the cache** (maven, gradle, npm/yarn/pnpm) — the tool is configured to use `$CACHE_DIRECTORY`
  directly (`MAVEN_USER_HOME`, `GRADLE_USER_HOME`, `NPM_CONFIG_CACHE`, ...).
  `MAVEN_USER_HOME` is exported because that is what `mvnw` resolves `wrapper/dists` under — the counterpart of
  Gradle's. Maven 3 itself ignores it and reads `~/.m2/settings.xml`, so `create_m2_dir` writes settings.xml to
  both locations; dropping the second copy would let anything that *does* honour the variable fall back to
  `~/.m2/repository` and lose the cache without failing.
- **Symlinked into the cache** (sdkman, nvm, pyenv) — these runtimes are *partly baked into the rootfs* at image
  build time and partly installed during a task, and their state directory path is fixed by the tool. So
  `cache_link_runtime` seeds the cache from whatever the image shipped (`cp --no-clobber`, first run only), deletes
  the directory and symlinks it to the cache volume. The tool then installs straight into the cache with no copy on
  either side.

  This replaced per-runtime lz4 archives. A JDK went through lz4 twice on every build, and a truncated archive — a
  full disk, a killed build — took the whole runtime with it: `tar` exited mid-extract, the archive was discarded,
  and the task carried on with half a JDK until something failed far away from the cause.

Docker image caching for Testcontainers is handled in `assets/includes/docker/`.

### S3 Cache Tier (`assets/includes/s3cache.sh`)

**Experimental**, like `testcontainers.rootless`: off by default, and its CI job sits outside the `release-gate`
anchor so a bucket outage can't block a publish. Option names and the key layout are still open to change.

An optional second tier that outlives the worker, since a Concourse task cache dies with the worker it lives on.
`s3cache_restore`/`s3cache_save` use `rclone copy`. Points worth
knowing before changing it:

- It is only consulted when the **local** tier is cold; a warm worker makes no network calls.
- Everything it syncs now lives directly in `$CACHE_DIRECTORY`, so "cold" uniformly means "the directory is empty"
  (`gradle_cache_is_cold`, and the equivalent checks in maven/`restore_directory_caches`). npm/yarn/pnpm and
  user-declared `extra_dirs` go through `restore_directory_caches`/`save_directory_caches` in `bashrc.sh`; note their
  paths are exported *before* the initialize callbacks run, deliberately — the restore callback needs them.
- Every key is scoped to `pipeline/$S3_CACHE_SCOPE`, so a restore only downloads what that scope uploaded.
  `rclone copy` has no way to fetch a subset of a key, so widening that scope would make every cold start pay for the
  whole bucket; it would need a per-pipeline manifest plus `rclone copy --files-from` first.
- The scope has to be passed in as a task param. It was `BUILD_TEAM_NAME`/`BUILD_PIPELINE_NAME` at first, which is
  wrong twice over: a **task** container gets none of the `BUILD_*` metadata (only resource containers do, so it
  silently resolved to `unknown/unknown` and every pipeline shared one cache), and reading it in `in` instead would
  bake whichever pipeline built the rootfs first into a volume that is content-addressed by `source` and shared
  between all of them. Don't reach for build metadata at task time.
- `s3cache_restore` returns `0` complete / `1` partial / `2` skipped. Callers that clean up after a partial restore
  (gradle's and maven's `wrapper/dists`) must check for `1` specifically — treating `2` the same way deletes a good
  local restore. Both wrapper dirs need that cleanup because each launcher treats the unpacked directory's mere
  existence as proof it is complete, and would run a truncated distribution rather than redownload it.
- A marker file under `$CACHE_DIRECTORY/.s3cache` is touched after **both** restore and save. Touching it after
  restore is what stops a cold start from re-uploading everything it just downloaded.
- The save-side dirty check (`find -newer` against that marker) runs the caller's `--exclude` patterns through
  `s3cache_find_excludes` first. Without that a single `*.lock` or `*.lastUpdated` marks the whole cache dirty and
  every build pays a listing plus a transfer of nothing.
- The docker image cache (`$CACHE_DIRECTORY/docker`) is deliberately **not** in this tier — layers are already
  content-addressed and registry-served, and would dominate the bucket.
- `bashrc.sh` defines no-op fallbacks for both functions, because the runtime plugins call them unconditionally and
  an undefined function in an initialize callback exits 127 and aborts the task.
- Nothing here may fail a build.

Integration-tested against the `floci` AWS emulator in `docker-compose.yml`:

```bash
TEST=s3-cache ./build-and-test.sh
```

`example/tests/s3-cache/task.yml` declares no `caches:` block at all, so every container starts with an empty local
tier — the "worker was rebuilt" case this tier exists for, without having to clear anything mid-run. The first run
populates the bucket, the second can only be warm via S3.

Don't assert on the `Restoring ... from the S3 cache` log line: rclone treats a copy from a key that doesn't exist yet
as a success, so that line proves an attempt was made, not that anything transferred. Two things are safe to match
instead, and `example/tests/s3-cache/test.env` uses both:

- `[cache] restore <key> from=s3 files=<n>`, emitted *after* the transfer with the count of what the build actually
  got, plus a `FORBID_IN_OUTPUT` on `from=(none|local)` for the maven and gradle keys and on `tier s3=disabled`.
- `S3 RESTORE VERIFIED`, which the task prints only when all four dependency caches are populated by the time the
  task body starts. The task never demands it itself, because it cannot tell which run it is.

The restored caches are then actually used — the second run builds with the wrapper it pulled out of the bucket. That
is the only thing that catches metadata an object store does not carry on its own: rclone runs with `--metadata`
because an S3 object has no POSIX mode, and without it a restored `bin/mvn` comes back `0644` and the build dies at
`exec: Permission denied`. Note that `--size-only` means already-uploaded objects are never revisited, so a bucket
filled before that flag existed keeps handing back mode-less files until its prefix is cleared.

In CI the same task runs as the `test-s3-cache` job in `ci/pipeline.yml`, against a real bucket, driven by
`test-experimental` rather than the gating `test` job. This is the one test whose `source` CI cannot take from its
test directory, since the local one points at floci, so that resource is declared inline in `ci/pipeline.yml`
instead. Which object store backs it is deliberately not decided in this repo: it is public, so it names only generic
`((s3-cache-bucket))`/`endpoint`/`region`/`prefix` vars plus
`((s3-cache-access-key-id))`/`((s3-cache-secret-access-key))` from Vault, and whoever deploys the pipeline supplies
the values. Don't reintroduce a provider name here.

### Adding a New Runtime

1. Create `assets/installers/<name>.sh` — export `<name>_get_dependencies()` returning Debian packages, and
   `<name>_install()` for any host-side work
2. Create `assets/hooks/customize-NN-<name>.sh` — install the runtime inside the chroot
3. Create `assets/includes/<name>.sh` — register initialize/teardown callbacks for caching; source it from
   `assets/includes/bashrc.sh`
4. Wire the new installer into `assets/in` (source it, call `*_get_dependencies`, call `*_install`)
5. Add the new `source` options to `README.md`
6. Add a test directory under `example/tests/` and a matching resource + job in `ci/pipeline.yml` and
   `example/pipeline.yml`

## Local Concourse Stack

`docker-compose.yml` spins up a full Concourse cluster for local testing:

- `web` — Concourse ATC at `http://localhost:8080`
- `worker` — privileged worker using containerd runtime
- `registry` — local Docker registry at `localhost:5000`
- `git-server` — serves `example/` and `ci/` over HTTP, at the paths CI's git resource has them
- `apt-cacher` — apt-cacher-ng proxy at port `3142` to speed up repeated `mmdebstrap` runs
- `floci` — local AWS emulator at port `4566`, used as the S3 endpoint when testing the `s3_cache` tier

Keys in `keys/` are pre-generated for the local stack.

## CI Pipeline

`ci/pipeline.yml` defines the production pipeline on Concourse:

- **build** → builds and pushes `:dev` tag to Docker Hub
- **test** → the release gate. Runs `ci/tasks/run-tests.sh`, which drives the gating `test-<name>` jobs twice each
- **test-experimental** → the same, for `s3-cache` and `testcontainers-rootless`
- **test-<name>** → one job per directory under `example/tests/`, each running that test's `task.yml` against a
  runtime built from its `source.yml`. None of them trigger on their own
- **publish-major/minor/patch** → bumps semver, pushes `:latest` + version tag, creates GitHub release

The publish jobs gate on the `release-gate` anchor at the top of `ci/pipeline.yml`, which is now just `test`; the set
of tests it covers is the `gating-tests` anchor next to it. `s3-cache` and `testcontainers-rootless` are deliberately
outside it and run from `test-experimental`: the first needs a reachable bucket, the second kernel support for
rootless containers, and neither should be able to block publishing a resource that works without them.

`ci/tasks/run-tests.sh` triggers jobs through `fly`, so the `test` jobs need `((fly-username))`/`((fly-password))`
for their own team. Everything else it needs — the ATC URL, team and pipeline name — Concourse injects into every
task, which is what lets the same script run unchanged against the docker-compose stack.

This repo is public, so `ci/pipeline.yml` deliberately contains **no** concrete values - only `((var))` references -
and no naming tied to the infrastructure it happens to run on, such as which object store backs the S3 cache. It is
deployed from a private repo that supplies those values, with credentials resolving from Vault at runtime. Keep it
that way: a new setting belongs here as a `((var))`, never as a literal.

There is deliberately no vars file in this repo either. Every test's runtime `source` comes straight from
`example/tests/<name>/source.yml`, which the deployment side globs and passes in as `SOURCE_<NAME>` vars, so adding a
test needs no change on that side at all.

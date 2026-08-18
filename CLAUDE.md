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
# Start the local Concourse stack and run the test pipeline (requires fly CLI and Docker):
./build-and-test.sh

# Run a specific example pipeline instead of the default:
PIPELINE_FILE=pipeline-maven.yml ./build-and-test.sh

# Recreate the pipeline from scratch:
RECREATE_PIPELINE=true ./build-and-test.sh
```

The test script:

1. Builds and pushes the resource image to the local registry (`localhost:5000`)
2. Logs into the local Concourse at `http://localhost:8080` (user: `test`, pass: `test`)
3. Sets and triggers the `setup-runtime-test` pipeline
4. Runs a second time to verify that no downloading occurs (cache hit check)

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
- Runs `TEARDOWN_CALLBACKS` on `EXIT` trap (registered by each `includes/*.sh` to save/compress caches)
- Prunes the cache if it exceeds `MAX_CACHE_SIZE_MB`

Docker image caching for Testcontainers is handled in `assets/includes/docker/`.

### Adding a New Runtime

1. Create `assets/installers/<name>.sh` — export `<name>_get_dependencies()` returning Debian packages, and
   `<name>_install()` for any host-side work
2. Create `assets/hooks/customize-NN-<name>.sh` — install the runtime inside the chroot
3. Create `assets/includes/<name>.sh` — register initialize/teardown callbacks for caching; source it from
   `assets/includes/bashrc.sh`
4. Wire the new installer into `assets/in` (source it, call `*_get_dependencies`, call `*_install`)
5. Add the new `source` options to `README.md`

## Local Concourse Stack

`docker-compose.yml` spins up a full Concourse cluster for local testing:

- `web` — Concourse ATC at `http://localhost:8080`
- `worker` — privileged worker using containerd runtime
- `registry` — local Docker registry at `localhost:5000`
- `git-server` — serves `example/` over HTTP for test pipelines
- `apt-cacher` — apt-cacher-ng proxy at port `3142` to speed up repeated `mmdebstrap` runs

Keys in `keys/` are pre-generated for the local stack.

## CI Pipeline

`ci/pipeline.yml` defines the production pipeline on Concourse:

- **build** → builds and pushes `:dev` tag to Docker Hub
- **test** → runs `example/task.yml` using the `:dev` image
- **publish-major/minor/patch** → bumps semver, pushes `:latest` + version tag, creates GitHub release

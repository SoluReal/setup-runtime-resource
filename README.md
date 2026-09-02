# setup-runtime-resource

A [Concourse](https://github.com/concourse/concourse) resource to setup a runtime environment for your tasks. This
resource is inspired by the setup github actions like [actions/setup-java](https://github.com/actions/setup-java)
and [actions/setup-node](https://github.com/actions/setup-node).

It leverages `mmdebstrap` to create a lightweight Debian rootfs with the tools you need without
requiring root. Due to concourse resource caching, the rootfs is only created once and reused for subsequent tasks.

Previously teams created their own images, pushed them to a registry and used them in their pipelines. This resource
provides a more convenient way to setup a runtime environment for your tasks without the need for a build step and a
registry.

## How it can be used with Concourse

To use this resource in your Concourse pipeline, you need to define the resource type and then the resource itself.

```yaml
resource_types:
  - name: setup-runtime-resource
    type: registry-image
    source:
      repository: SoluReal/setup-runtime-resource
      tag: latest

resources:
  - name: setup-runtime
    type: setup-runtime-resource
    source:
      java:
        version: 21
      maven:
        version: 3.9.6
      testcontainers:
        enabled: true
```

In your job, you can use the resource as an image for your task:

```yaml
jobs:
  - name: build
    plan:
      - in_parallel:
          - get: setup-runtime
          - get: my-source-code
      - task: build-project
        image: setup-runtime
        privileged: true # Required for Testcontainers/Docker
        config:
          platform: linux
          args:
            - -ec
            - |
              cd my-source-code
              mvn clean install
```

## Global resources

If you are using the same resource configuration for multiple pipelines, you benefit a lot
from [concourse global resources](https://concourse-ci.org/global-resources.html). Run your concours web instance with
`--enable-global-resources`.

## Options

The resource `source` configuration supports the following options:

| Option                        | Description                                                                                                               | Default |
|-------------------------------|---------------------------------------------------------------------------------------------------------------------------|---------|
| `dependencies`                | A list of Debian packages to install.                                                                                     | `[]`    |
| `hook`                        | A bash script to run inside the rootfs during creation.                                                                   | `""`    |
| `verbose`                     | Enable verbose logging during rootfs creation.                                                                            | `false` |
| `debug`                       | Enable debug mode, providing info like cache size at shutdown.                                                            | `false` |
| `sdkman.enabled`              | Enable SDKMAN.                                                                                                            | `false` |
| `java.version`                | The default Java version to install via SDKMAN. Look at the candidate list for java.                                      | `""`    |
| `java.extra_versions`         | A list of additional Java versions to install. Use `sdk use java <version>` in your code to switch to that version.       | `[]`    |
| `maven.version`               | The Maven version to install via SDKMAN.                                                                                  | `""`    |
| `maven.wrapper`               | Ensure Maven cache environment variables are set even if `maven.version` is not provided (for use with Maven wrapper).    | `false` |
| `gradle.version`              | The Gradle version to install via SDKMAN.                                                                                 | `""`    |
| `gradle.wrapper`              | Ensure Gradle cache environment variables are set even if `gradle.version` is not provided (for use with Gradle wrapper). | `false` |
| `pyenv.enabled`               | Enable pyenv.                                                                                                             | `false` |
| `golang.version`              | The Go version to install.                                                                                                | `""`    |
| `nvm.enabled`                 | Enable NVM.                                                                                                               | `false` |
| `nodejs.version`              | The Node.js version to install via NVM.                                                                                   | `""`    |
| `nodejs.yarn.version`         | The Yarn version to install.                                                                                              | `""`    |
| `nodejs.pnpm.version`         | The PNPM version to install.                                                                                              | `""`    |
| `nodejs.bun.version`          | The bun version to install.                                                                                               | `""`    |
| `testcontainers.enabled`      | Enable Docker-in-Docker support for Testcontainers. You need to start the task with `privileged: true`                    | `false` |
| `testcontainers.rootless`     | Run a rootless podman daemon instead of dockerd (see [Rootless testcontainers](#rootless-testcontainers) below).          | `false` |
| `telemetry.disable`           | Disable telemetry (if any).                                                                                               | `false` |
| `minimal_image`               | Strip build/IDE-only content to shrink the rootfs (see [Minimal image](#minimal-image) below).                            | `false` |
| `dependency_download_retries` | Number of times to retry a failed dependency download (`curl`) during rootfs creation. `0` disables retries.              | `0`     |
| `s3_cache.enabled`            | **Experimental.** Keep the dependency caches in an S3-compatible bucket as well (see [S3 cache](#s3-cache)).              | `false` |
| `s3_cache.bucket`             | Bucket to store the cache in. Required when `s3_cache.enabled` is set.                                                    | `""`    |
| `s3_cache.endpoint`           | S3 endpoint URL. Leave empty for AWS S3.                                                                                  | `""`    |
| `s3_cache.region`             | Bucket region.                                                                                                            | `""`    |
| `s3_cache.prefix`             | Extra key prefix inside the bucket.                                                                                       | `""`    |
| `s3_cache.provider`           | rclone's S3 provider hint (`AWS`, `Minio`, `Scaleway`, ...). `Other` suits any store rclone has no quirks for, Backblaze B2 included. | `Other` |
| `s3_cache.transfers`          | Parallel object transfers.                                                                                                | `12`    |
| `s3_cache.always_restore`     | Also consult S3 when the local cache is already warm. Adds a listing on every build.                                      | `false` |
| `s3_cache.gradle_build_cache` | Also cache Gradle's task output cache (`build-cache-1`). See the caveat below.                                            | `false` |
| `s3_cache.extra_dirs`         | Your own `$CACHE_DIRECTORY` subdirectories to cache.                                                                      | `[]`    |
| `s3_cache.rclone_version`     | Pin a specific rclone version instead of tracking the current release.                                                    | `""`    |

## Tasks run as a non-root user

Tasks using this resource run as the unprivileged `runtime` user (uid 1000), not as `root`. `HOME` is
`/home/runtime`, and the runtimes installed under `/var/runtimes` are owned by that user so `sdk install`,
`nvm install` and pyenv still work at task time. Concourse chowns input, output and cache volumes to the task user
([concourse/concourse#9593](https://github.com/concourse/concourse/pull/9593), Concourse 8.3.0+), so steps around your
task keep working unchanged.

The one exception is `testcontainers.enabled: true` with `testcontainers.rootless: false`: `dockerd` needs real root, so
that combination still runs the task as `root`. Prefer
[rootless testcontainers](#rootless-testcontainers) instead.

## Minimal image

When `minimal_image: true` is set, the resource strips content from the rootfs that isn't needed to compile or
run code, but is not safe to remove unconditionally for every user:

- Every installed JDK's `lib/jmods` (only used by the `jlink` tool to build a custom trimmed Java runtime) and
  `lib/src.zip` (the JDK's own source archive, used only by IDEs for source lookup/hover-docs).
- Go's own `test/` (the Go compiler's test suite) and `api/` (API-compatibility check data) directories - not
  used by `go build`, `go test`, or `go vet` on your code.
- Node's `include/` (V8 + Node headers) - only used by `node-gyp` to compile native addons (e.g. `bcrypt`,
  `sharp`), not to run `node`/`npm`/`yarn`/`pnpm`.

This can shave several hundred MB off the rootfs. It's opt-in and defaults to `false` because if your pipeline
actually runs `jlink` against the installed JDK or compiles native npm addons, this will break it. This may
become the default in a future 1.x release once it's had more real-world exposure; until then, opt in
explicitly if you want the smaller image.

## Retries

By default, `setup-runtime-resource` does not retry failed downloads (SDKMAN, NVM, bun, pyenv, Go, and the
Docker apt key) - a transient network error during rootfs creation fails the resource straight away. Set
`dependency_download_retries` to have it retry those downloads:

```yaml
source:
  dependency_download_retries: 3
```

This is implemented via curl's own `--retry` handling, which backs off exponentially between attempts (1s,
2s, 4s, ..., capped at 10 minutes).

## Supported runtime options

The generated rootfs supports a couple of runtime environment variables. These runtime environment variables
are only applied if a bash script is executed.

```yaml
jobs:
  - name: build
    plan:
      - get: setup-runtime
      - task: build-project
        image: setup-runtime
        params:
          DEBUG: true # Specify the params here.
        config:
          platform: linux
          run:
            path: bash
            args:
              - -ec
              - |
                echo "Hello from setup-runtime-resource!"              
```

The following runtime environment variables are available:

| Option              | Description                                                             | Default |
|---------------------|-------------------------------------------------------------------------|---------|
| `DEBUG`             | Enable debug loggging on runtime                                        | `false` |
| `ENABLE_CACHE`      | Enable caching                                                          | `true`  |
| `S3_CACHE_ACCESS_KEY_ID`     | Access key for the [S3 cache](#s3-cache). Required when it is enabled.                          | `""`    |
| `S3_CACHE_SECRET_ACCESS_KEY` | Secret key for the [S3 cache](#s3-cache). Required when it is enabled.                          | `""`    |
| `S3_CACHE_SCOPE`             | Which cache in the bucket this build uses - see [Scope](#scope).                                | `default` |
| `S3_CACHE_RESTORE_MAX_DURATION` | Time budget for restoring from S3 before giving up and building without it.                 | `10m`   |
| `S3_CACHE_SAVE_MAX_DURATION`    | Time budget for the upload at the end of a task. A cut-short upload resumes next build.      | `5m`    |

## Docker registry logins

When `testcontainers.enabled: true`, you can log the task in to one or more Docker registries
before your task script runs, using numbered params:

```yaml
jobs:
  - name: build
    plan:
      - get: setup-runtime
      - task: build-project
        image: setup-runtime
        privileged: true
        params:
          DOCKER_LOGIN_1_REGISTRY: index.docker.io
          DOCKER_LOGIN_1_USERNAME: ((dockerhub-username))
          DOCKER_LOGIN_1_PASSWORD: ((dockerhub-password))
          DOCKER_LOGIN_2_REGISTRY: registry.example.com
          DOCKER_LOGIN_2_USERNAME: ((example-registry-username))
          DOCKER_LOGIN_2_PASSWORD: ((example-registry-password))
        config:
          platform: linux
          run:
            path: bash
            args:
              - -ec
              - docker pull registry.example.com/some/image
```

Numbering starts at `1` and must be contiguous; the first missing `DOCKER_LOGIN_<n>_REGISTRY`
stops the loop. Logins run for both dockerd and rootless podman (via the `podman-docker` shim),
and complete before your task's own script starts executing. If no `DOCKER_LOGIN_*` params are
set, this is a no-op.

## SDKMAN

[SDKMAN](https://sdkman.io/) is used to install JVM related tools. The `.sdkmanrc` file is supported by this resource.
This way you can include the used JDK version in source control and let it be updated by
e.g. [renovatebot](https://docs.renovatebot.com/).

Example resource configuration:

```yaml
resources:
  - name: setup-runtime
    type: setup-runtime-resource
    source:
      sdkman:
        enabled: true
```

Job example:

```yaml
jobs:
  - name: build
    plan:
      - in_parallel:
          - get: setup-runtime
          - get: my-source-code
      - task: build-project
        image: setup-runtime
        config:
          platform: linux
          args:
            - -ec
            - |
              cd my-source-code
              sdk env install
              ./mvnw clean install
```

## NVM

[nvm](https://github.com/nvm-sh/nvm) is used to install and manage Node.js versions. The `.nvmrc` file is supported by
this resource. This allows you to commit the required Node.js version to source control and keep it up to date using
tools like [renovatebot](https://docs.renovatebot.com/).

Example resource configuration:

```yaml
resources:
  - name: setup-runtime
    type: setup-runtime-resource
    source:
      nvm:
        enabled: true
```

Job example:

```yaml
jobs:
  - name: build
    plan:
      - in_parallel:
          - get: setup-runtime
          - get: my-source-code
      - task: build-project
        image: setup-runtime
        config:
          platform: linux
          args:
            - -ec
            - |
              cd my-source-code
              nvm install
              # Enable corepack (optional)
              corepack enable
              npm ci
              npm run build
```

## Pyenv

[pyenv](https://github.com/pyenv/pyenv) is used to install and manage Python versions. The `.python-version` file is
supported by this resource. This allows you to commit the required Python version to source control and keep it up to
date using tools like [renovatebot](https://docs.renovatebot.com/).

Example resource configuration:

```yaml
resources:
  - name: setup-runtime
    type: setup-runtime-resource
    source:
      pyenv:
        enabled: true
```

Job example:

```yaml
jobs:
  - name: build
    plan:
      - in_parallel:
          - get: setup-runtime
          - get: my-source-code
      - task: build-project
        image: setup-runtime
        config:
          platform: linux
          args:
            - -ec
            - |
              cd my-source-code
              # Skip-existing is required to prevent pyenv from failing when the version is already installed.
              pyenv install --skip-existing
              pyenv local
              pip install -r requirements.txt
              pytest
```

## Gradle

Gradle can be either installed at resource gathering time or at runtime using the gradlew wrapper.

The gradle.properties file is generated automatically to configure caching variables.

To override the gradle.properties use:

```yaml
jobs:
  - name: build
    plan:
      - get: setup-runtime
      - task: build-project
        image: setup-runtime
        params:
          # This will replace the default value
          GRADLE_PROP_org_gradle_parallel: false
          GRADLE_PROP_org.gradle.jvmargs: -Xmx4096
        config:
          platform: linux
          run:
            path: bash
            args:
              - -ec
              - |
                echo "Hello from setup-runtime-resource!"
```

## Caching

This resource tries to be a batteries included resource for building and testing your projects
with [Concourse CI](https://github.com/concourse/concourse). The resource tries to configure as much package managers
as possible to let it work with concourse caching.

Please open an issue if your package manager is not supported or not working for your usecase.

### Where the caches live

`MAVEN_USER_HOME` (`$CACHE_DIRECTORY/maven`, holding both the local repository and the distributions `mvnw`
downloads), `GRADLE_USER_HOME` (`$CACHE_DIRECTORY/gradle`) and the npm/yarn/pnpm caches all live *directly* in the
task cache directory. Nothing is compressed into an archive first, so a build no longer pays a full
compress-and-extract of the whole dependency tree on every run - which for a multi-GB Gradle cache is a meaningful
chunk of build time.

SDKMAN, NVM and pyenv get there differently but end up the same way. Their state directories sit at a path the tool
fixes (`$SDKMAN_DIR/candidates`, `$NVM_DIR/versions`, `$PYENV_ROOT/versions`) and are partly baked into the rootfs at
image build time, so they cannot simply be pointed elsewhere. Instead the directory is seeded into the task cache
once from whatever the image shipped, and then symlinked to it - after which `sdk install`, `nvm install` and
`pyenv install` write straight into the cache volume.

### Reading the cache log

A build logs what it moved, and nothing else. Every line means something was restored or saved - there are no lines
reporting zero of something, so a first build against empty caches prints almost nothing here, and a warm build
that installs nothing new prints no `save` lines at all:

```
[cache] tier s3=enabled scope=my-pipeline bucket=my-ci-cache
[cache] restore maven/repository from=s3 files=1743 in=14s
[cache] restore gradle/modules-2 from=local files=8210
[cache] restore sdkman from=local candidates=3
[cache] restore pyenv from=rootfs versions=1
[cache] save maven/repository to=s3 files=1802 in=9s
```

`from=` is the question worth asking of a slow build:

| Value | Meaning |
| --- | --- |
| `local` | The Concourse task cache already held it. No network call was made - the fast path. |
| `s3` | The task cache was cold and the [S3 tier](#s3-cache) filled it. |
| `rootfs` | It came with the image, baked in at `in` time - the [Docker image cache](#docker-image-cache), or the version the image shipped on a first build. |

A key with no line against it had nothing cached anywhere, and whatever it covers is about to be downloaded from
upstream. The flip side is that silence alone cannot tell you a cache is *working* - only that it moved nothing.
The `tier s3=...` line below is what distinguishes a quiet warm build from a tier that never ran.

A `tier s3=disabled reason=...` line says why the S3 tier is sitting the build out - `no-credentials` when
`S3_CACHE_ACCESS_KEY_ID`/`S3_CACHE_SECRET_ACCESS_KEY` were not passed as task params, `no-bucket`,
`no-rclone`, or `caching-disabled` when `ENABLE_CACHE` is off. Nothing in the cache layer may fail a build, so
without that line a misconfigured tier is indistinguishable from a warm cache: the build just quietly downloads
everything, every time, and still goes green.

The lines are meant to be grepped as well as read. `[cache] <verb> <key> <field>=<value>...` is stable; new fields
get appended rather than changing the ones already there.

### Docker image cache

Docker images that are in your job will be automatically cached. This prevents the image from being downloaded every
time your job runs when using e.g. [testcontainers](https://testcontainers.com/).

## S3 cache

> **Experimental.** Off by default, and not part of the release gate - the job covering it in CI depends on a
> reachable bucket, so it is deliberately not allowed to block a publish. Expect the option names and key layout to
> still change.

The Concourse task cache is local to the worker that ran your build. If that worker is rebuilt - autoscaled away,
recreated, or simply running with `--ephemeral` - the cache goes with it and the next build refetches every
dependency from Maven Central, npm, or wherever else. Concourse cannot help here: a cache volume is bookkeeping
tied to a live, registered worker, so it cannot outlive one.

`s3_cache` adds a second tier in an S3-compatible bucket that survives all of that:

```yaml
resources:
  - name: setup-runtime
    type: setup-runtime-resource
    source:
      gradle:
        wrapper: true
      s3_cache:
        enabled: true
        bucket: my-ci-cache
        endpoint: https://s3.eu-central-003.backblazeb2.com
        region: eu-central-003
```

Credentials are **task params**, not `source`:

```yaml
      - task: build
        image: setup-runtime
        params:
          S3_CACHE_ACCESS_KEY_ID: ((s3-access-key))
          S3_CACHE_SECRET_ACCESS_KEY: ((s3-secret-key))
```

`check` hashes the resource `source` into its version, so keeping credentials out of it means rotating them doesn't
rebuild your whole rootfs - and no secrets end up in pipeline config.

### How it behaves

The local task cache stays the fast path and is always tried first. S3 is consulted **only when the local cache is
cold** - a rebuilt worker, or a first build. A warm worker makes no network
calls at all. On the way out, only genuinely new files are uploaded; a build that added no dependencies skips the
upload entirely without so much as a listing request.

Transfers are per-object rather than one big archive, so both directions move only what the other side is missing,
and an interrupted transfer simply resumes on the next build. Cache failures never fail a build - a bad credential
or an unreachable bucket logs a warning and the build carries on downloading normally.

### What gets cached

| Cache | Uploaded |
|---|---|
| Maven `repository`, `wrapper/dists` | yes |
| Gradle `caches/modules-2`, `wrapper/dists` | yes |
| npm, yarn and pnpm caches | yes |
| Anything in `s3_cache.extra_dirs` | yes |
| Gradle `build-cache-1` | only with `s3_cache.gradle_build_cache` |
| Gradle `caches/jars-9`, `configuration-cache` | no - derived, and tied to a Gradle version or a checkout path |
| The [Docker image cache](#docker-image-cache) | no - see below |

Everything uploaded is keyed by scope - see [Scope](#scope).

Maven's `*.lastUpdated` and `_remote.repositories` files are deliberately excluded - they record a *failed*
resolution, so restoring them would make later builds skip retrying an artifact that may since have become
available.

The [Docker image cache](#docker-image-cache) is **not** part of this tier and stays local to the worker. Image
layers are already content-addressed and served by a registry that is itself a CDN, so putting a second copy in an
object store in front of it buys little, and image caches are large enough to dominate the bucket. A rebuilt
worker repulls its images from the registry as usual.

### Caching your own tools

Any tool that can be told where to keep its cache can join in. Point it at a subdirectory of `$CACHE_DIRECTORY`
(which this resource exports into your task), then name that subdirectory in `extra_dirs`:

```yaml
source:
  s3_cache:
    enabled: true
    bucket: my-ci-cache
    extra_dirs:
      - my-tool
```

Most build tools take the directory from config or an environment variable, so this is usually a one-liner in the
tool's own configuration:

```js
// somewhere in your build config
cacheDir: process.env.CACHE_DIRECTORY ? `${process.env.CACHE_DIRECTORY}/my-tool` : undefined,
```

**Gradle's `build-cache-1`** holds task *outputs* rather than downloaded dependencies, and is off by default because
it behaves completely differently: entries are produced on every code change, so unlike a dependency cache it
uploads on essentially every build, for a much lower hit rate per byte stored. If you enable it, Gradle's own
[remote build cache](https://docs.gradle.org/current/userguide/build_cache.html) is still the better-engineered
option; this is a cruder directory sync.

### Scope

Every cache is keyed as `<prefix>/pipeline/<scope>/...`, so a restore only ever downloads what was uploaded under the
same scope. Name it with the `S3_CACHE_SCOPE` task param:

```yaml
      - task: build
        image: setup-runtime
        params:
          S3_CACHE_ACCESS_KEY_ID: ((s3-access-key))
          S3_CACHE_SECRET_ACCESS_KEY: ((s3-secret-key))
          S3_CACHE_SCOPE: my-pipeline
```

Concourse tells a task nothing about the build it belongs to, so this cannot be worked out for you. Left unset, every
build sharing a bucket prefix shares one cache - fine for a single pipeline, and probably not what you want for
several, since each would pull down dependencies it has no use for.

The trade-offs to be aware of: a new scope always starts cold, renaming one orphans its cache, and total storage grows
with the number of scopes - bound it with a bucket lifecycle rule (see [Bucket retention](#bucket-retention)).

### Bucket retention

Two things to set on the bucket itself:

- **Add a lifecycle rule** expiring objects after 90-180 days. Nothing is ever deleted from the bucket otherwise:
  uploads use `rclone copy`, not `sync`, because a mirroring `sync` would delete everything the local cache happens
  not to be holding.
- **Leave versioning off**, or add a noncurrent-version expiration rule. Versioning plus repeated overwrites quietly
  accumulates old versions that never show up in a normal bucket listing.

Note that lifecycle rules expire on **object age, not last access**, and because unchanged files are never
re-uploaded an object's timestamp never refreshes. So every object is deleted N days after it was first uploaded no
matter how heavily it is used, and the cache turns over completely every N days. That is why the suggested window is
much longer than the 30 days Gradle uses for its own local cleanup, which really is access-based.

Turnover is not harmful, just wasteful: a cold restore misses the expired objects, the build fetches them from
upstream as usual, and the next upload puts them back. Nothing breaks, and no build fails.

Because the bucket is never pruned by content, a pipeline's pool grows towards "every dependency this pipeline has
used within the window" rather than its current working set - a dependency that a build stops using is still restored
until the lifecycle rule expires it. Keeping the window tight is what keeps a cold restore close to the size of the
working set.

## Rootless testcontainers

With `testcontainers.rootless: true`, [podman](https://podman.io/) is used instead of `dockerd`, running as a real
non-root user (`runtime`) instead of root. A `docker` command is still provided (via `podman-docker`) so existing
`docker build`/`docker run` calls and Testcontainers itself keep working unmodified.

You still need `privileged: true` on the task. However, you can run your concourse worker with
`--containerd-privileged-mode=fuse-only` to limit the privileges your tasks run with.
See [Concourse security hardening docs](https://concourse-ci.org/docs/operation/security-hardening/) for more info.

### Worker requirements

**The host must allow unprivileged user namespaces.** Rootless podman creates user namespaces, which on Ubuntu and other
AppArmor kernels is blocked for non-root processes by the `kernel.apparmor_restrict_unprivileged_userns`
sysctl. If your host uses Apparmor you need to disable it or run with a custom profile. To disable:

```
sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

If it is still enabled, podman fails to start and the task aborts with podman's own logs.

Note, only Concourse >8.3.0 will work with rootless + fuse-only mode.

### Limitations of rootless containers

**Containers cannot bind ports below 1024 internally.**
**[Ryuk]([https://github.com/testcontainers/moby-ryuk](https://podman-desktop.io/tutorial/testcontainers-with-podman)) doesn't work with rootless podman**

Contributions are welcome! Please follow these steps to contribute:

1. Fork the repository on GitHub.
2. Create a new branch for your feature or bugfix.
3. Make your changes and ensure they are well-tested.
4. Submit a pull request with a clear description of your changes.

If you want an additional version manager, please open an issue.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

# setup-runtime-resource

A [Concourse](https://github.com/concourse/concourse) resource to setup a runtime environment for your tasks. This
resource is inspired by the setup github actions like [actions/setup-java](https://github.com/actions/setup-java)
and [actions/setup-node](https://github.com/actions/setup-node)

It leverages `mmdebstrap` and `fakechroot` to create a lightweight Debian rootfs with the tools you need without
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

| Option                   | Description                                                                                                               | Default |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------|---------|
| `dependencies`           | A list of Debian packages to install.                                                                                     | `[]`    |
| `hook`                   | A bash script to run inside the rootfs during creation.                                                                   | `""`    |
| `verbose`                | Enable verbose logging during rootfs creation.                                                                            | `false` |
| `debug`                  | Enable debug mode, providing info like cache size at shutdown.                                                            | `false` |
| `sdkman.enabled`         | Enable SDKMAN.                                                                                                            | `false` |
| `java.version`           | The default Java version to install via SDKMAN. Look at the candidate list for java.                                      | `""`    |
| `java.extra_versions`    | A list of additional Java versions to install. Use `sdk use java <version>` in your code to switch to that version.       | `[]`    |
| `maven.version`          | The Maven version to install via SDKMAN.                                                                                  | `""`    |
| `maven.wrapper`          | Ensure Maven cache environment variables are set even if `maven.version` is not provided (for use with Maven wrapper).    | `false` |
| `gradle.version`         | The Gradle version to install via SDKMAN.                                                                                 | `""`    |
| `gradle.wrapper`         | Ensure Gradle cache environment variables are set even if `gradle.version` is not provided (for use with Gradle wrapper). | `false` |
| `pyenv.enabled`          | Enable pyenv.                                                                                                             | `false` |
| `golang.version`         | The Go version to install.                                                                                                | `""`    |
| `nvm.enabled`            | Enable NVM.                                                                                                               | `false` |
| `nodejs.version`         | The Node.js version to install via NVM.                                                                                   | `""`    |
| `nodejs.yarn.version`    | The Yarn version to install.                                                                                              | `""`    |
| `nodejs.pnpm.version`    | The PNPM version to install.                                                                                              | `""`    |
| `nodejs.bun.version`     | The bun version to install.                                                                                               | `""`    |
| `testcontainers.enabled` | Enable Docker-in-Docker support for Testcontainers. You need to start the task with `privileged: true`                    | `false` |
| `testcontainers.rootless` | Run a rootless podman daemon instead of dockerd (see [Rootless testcontainers](#rootless-testcontainers) below).         | `false` |
| `telemetry.disable`      | Disable telemetry (if any).                                                                                               | `false` |
| `minimal_image`          | Strip build/IDE-only content to shrink the rootfs (see [Minimal image](#minimal-image) below).                           | `false` |

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
| `MAX_CACHE_SIZE_MB` | When the cache size is over the MAX_CACHE_SIZE_MB, the cache is pruned. | `""`    |

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

You can run out of disk space pretty easily when caching aggressively without cache pruning. Although this resource
tries
to prune the cache automatically, it might not work in all cases.

Therefore it might be a good idea to set a `MAX_CACHE_SIZE_MB` paramt to prevent the cache from growing too large.

### Docker image cache

Docker images that are in your job will be automatically cached. This prevents the image from being downloaded every
time your job runs when using e.g. [testcontainers](https://testcontainers.com/).

## Rootless testcontainers

With `testcontainers.rootless: true`, a [podman](https://podman.io/) daemon is used instead of `dockerd`, running as
a real non-root user (`runtime`) instead of root. A `docker` command is still provided (via `podman-docker`) so
existing `docker build`/`docker run` calls and Testcontainers itself keep working unmodified against the podman
socket.

You still need `privileged: true` on the task - it's required either way, since Concourse's containerd runtime
denies non-privileged tasks both `/dev/fuse` and the ability to create user namespaces at all (this is enforced by
containerd itself, not something this resource can work around). What `rootless: true` buys you is defense in
depth: the container runtime that starts your test containers never actually runs as real root, so a container
escape from a test no longer hands out root on the task.

**This depends on a host-wide kernel toggle.** Rootless podman needs to create user namespaces, which on many
kernels is blocked for non-root processes by AppArmor's `apparmor_restrict_unprivileged_userns` restriction - even
inside a `privileged: true` task. If present, this resource relaxes that sysctl for the duration of the task and
restores it afterwards. That sysctl is **not scoped to your container** - while your task holds it relaxed, every
other container running on the same Concourse worker also has unprivileged user namespace creation available to
it. On a worker shared with other pipelines/teams, that's a real, if temporary, reduction in that worker's
hardening, not just a change to your own task. Consider whether that's acceptable for your worker pool before
enabling this.

**Worker `containerd-privileged-mode` needs to be `full`.** Concourse workers support a
`--containerd-privileged-mode=[full|fuse-only|ignore]` flag controlling what `privileged: true` tasks actually get.
`fuse-only` ("enough to use fuse-overlayfs") is not enough for this feature: it grants `/dev/fuse` and
`CAP_SYS_ADMIN`, but keeps a seccomp filter active and doesn't grant write access to the AppArmor sysctl above or
`CAP_NET_ADMIN`/`/dev/net/tun` for rootless networking - tested directly against a `fuse-only` worker, `docker run`
fails cleanly with `cannot set user namespace`. Only `full` mode (the default) works today.

Contributions are welcome! Please follow these steps to contribute:

1. Fork the repository on GitHub.
2. Create a new branch for your feature or bugfix.
3. Make your changes and ensure they are well-tested.
4. Submit a pull request with a clear description of your changes.

If you want an additional version manager, please open an issue.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

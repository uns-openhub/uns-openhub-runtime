# UNS OpenHub Controller Bundle (Registry)

> **Private initial release.** This generated repository is currently private.
> It may be made public later, but public visibility does not change the
> proprietary license or expose the private `uns-openhub-tools` source.

This bundle runs the UNS OpenHub Controller from registry images. It supports
three common cases:

- start only the local infrastructure
- start only the controller
- start both local infrastructure and controller

## Setup

You need Docker or Podman with Compose, plus access to the registry images
configured in `.env`. The examples use `docker compose`; with Podman use
`podman compose` with the same arguments.

### Fresh install without Git or GitHub CLI

The public `uns-openhub-bootstrap` release contains only a minimal Go
downloader and installers. This runtime repository and its release assets may
remain private. macOS and Linux users start without Git, GitHub CLI, Node,
Python, or `jq`:

```sh
curl -fsSL \
  https://github.com/uns-openhub/uns-openhub-bootstrap/releases/latest/download/install.sh |
  sh

"$HOME/.local/bin/uns-bootstrap" install
```

The installer verifies and installs `uns-bootstrap` under `~/.local/bin`.
Bootstrap releases use their own semantic version and embed the default
runtime version they install. It first tries that runtime release anonymously.
If the runtime is
private, it asks for a GitHub token using a hidden prompt and uses it only for
the release API requests; the token is not stored. Use a fine-grained,
expiring token limited to `uns-openhub-runtime` with read-only Contents
permission.

The bootstrap verifies the immutable offline runtime bundle, refuses an
unknown or non-matching non-empty destination, extracts it without links or
path traversal, verifies the matching private `uns` CLI, and starts that CLI's
init wizard. Re-running it for the same verified runtime safely reuses the
installation and resumes the wizard. If the destination contains a different
or unverifiable runtime, the error reports the found and requested versions
when available and prints commands for a side-by-side install or a safe
rename-and-retry. The init summary starts its copyable command sequence by
changing to the initialized runtime directory, so it also works when bootstrap
was launched elsewhere.

The default target is the stable per-user directory
`$HOME/uns-openhub-runtime`. To install beside the current working directory
instead:

```sh
"$HOME/.local/bin/uns-bootstrap" install \
  --dir "$PWD/uns-openhub-runtime"
```

Windows PowerShell:

```powershell
Invoke-WebRequest `
  https://github.com/uns-openhub/uns-openhub-bootstrap/releases/latest/download/install.ps1 `
  -OutFile install.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
& "$HOME\.local\bin\uns-bootstrap.exe" install
```

The Windows default is `$HOME\uns-openhub-runtime`. To install beside the
current PowerShell directory instead:

```powershell
& "$HOME\.local\bin\uns-bootstrap.exe" install `
  --dir (Join-Path $PWD "uns-openhub-runtime")
```

Use `uns-bootstrap version` to show the Bootstrap version and the Runtime
release it selects. The controller and custom PostgreSQL image tag is a third,
independent version boundary: read `release/manifest.json` → `imageTag` and the
effective `UNS_TAG`. Use
`uns-bootstrap install --version <runtime-version>` for an immutable older
runtime or `uns-bootstrap install --offline <bundle.tar.gz>` with its sibling
`.sha256` file for an offline installation. For unattended private downloads,
provide `UNS_GITHUB_TOKEN` through the host's secret mechanism rather than a
command-line argument.

### Existing runtime checkout

Run the commands from the runtime bundle directory. Use `./bin/uns` on
macOS/Linux or `.\bin\uns.cmd` in Windows PowerShell. The small launcher
selects the current platform and verifies a versioned CLI asset before running
it. A generated/offline bundle uses its local `.release` assets; a Git checkout
downloads the asset on first use. Public releases need no credential. A private
release prompts for a read-only GitHub token without displaying or storing it.

Recommended setup:

```sh
./bin/uns init -i
```

The wizard creates or updates `.env`, prepares local or Infisical settings, and
prints the `bin/uns runtime` commands to run next. Each of those commands shows
the exact `docker compose` or `podman compose` invocation before it runs it. For
a new `.env`, it pins `UNS_TAG` to the image version recorded when this runtime
was generated; an existing `.env` or explicit `UNS_TAG` override is preserved.
Passwords and access tokens requested by the wizard use hidden terminal input;
existing values can be kept without displaying them.

Manual setup:

1. Copy the environment template:

```sh
cp .env.example .env
```

2. Edit `.env` and set at least:

```env
UNS_REGISTRY=docker.io
UNS_REPO_PREFIX=unsopenhub
UNS_CONTROLLER_REPOSITORY=uns-openhub-controller
UNS_POSTGRES_REPOSITORY=uns-postgres
UNS_TAG=<controller/Postgres image version>
CONFIG_FILE=config-example.json
```

The controller image is private during the Runtime preview. Authenticate the
container engine before starting a mode that includes the controller:

```sh
docker login docker.io
# or
podman login docker.io
```

Use your Docker Hub username and an access token. The container engine stores
the credential in its own credential store; do not put it in `.env`. Docker
Hub image access is separate from the GitHub token used to download the
private Runtime.

These defaults resolve to:

```text
docker.io/unsopenhub/uns-openhub-controller:<version-or-latest>
docker.io/unsopenhub/uns-postgres:<version-or-latest>
```

`uns-postgres` remains public and does not require registry authentication. If
an existing `.env` still has `UNS_IMAGE_REPOSITORY`, replace it with
`UNS_CONTROLLER_REPOSITORY` and `UNS_POSTGRES_REPOSITORY` as shown above. The
Compose files retain safe defaults so regeneration does not overwrite the
preserved `.env`.

3. For local runs without Infisical, keep `CONFIG_FILE=config-example.json`.
   The default local Postgres password is read from `POSTGRES_PASSWORD` in
   `.env`. If you change `POSTGRES_USER` or `POSTGRES_DB`, update the same
   values in `configs/uns-openhub-controller/config-example.json`.

4. Edit the controller config only when your endpoints differ from the local
   defaults:

```text
configs/uns-openhub-controller/config-example.json
```

If you create another config file, set `CONFIG_FILE` in `.env` to that file
name.

The example configuration includes public UNS OpenHub package discovery. It
needs no GitHub token and scans public repositories under `uns-openhub`, but
offers only packages whose default branch and tagged release both carry a
compatible `unsDatahub` manifest. This includes core runtime packages such as
`uns-archiver` and `uns-api-global` when they publish compatible releases.
Existing installations keep their local config during a runtime refresh; to
opt in, copy the `addons.repositorySources` block from the new example into
the active controller config, then restart the controller. Do not replace an
existing config file wholesale, because it can contain operator-specific
endpoints and secret references.

The generated runtime uses PostgreSQL connection pooling. If an existing
configuration explicitly sets `pg.isPoolConnection` to `false`, change it to
`true` while applying the catalog migration, then restart the controller. A
single shared PostgreSQL client cannot safely serve the controller's concurrent
schema, authentication, and API reads.

### Optional: Infisical

Use Infisical only if you want the controller config to resolve secrets from
Infisical instead of `.env`.

1. Set this in `.env`:

```env
CONFIG_FILE=config-infisical-example.json
```

2. Edit `configs/uns-openhub-controller/config-infisical-example.json` and
   replace the endpoint placeholders.

3. Create the controller secret files:

```sh
./bin/uns dummy-secrets
```

Then edit:

```text
.secrets/infisical_token
.secrets/infisical_project_id
.secrets/infisical_site_url
```

The files mean:

- `infisical_site_url`: your Infisical URL, for example `https://app.infisical.com` or your self-hosted Infisical URL.
- `infisical_project_id`: open the target project in Infisical, go to Project Settings, and copy the Project ID.
- `infisical_token`: an access token for a Machine Identity that has access to the project secrets. The `bin/infisical-rotator` helper can create and refresh this file from `INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET`.

For the rotator, copy `infisical-rotator.env.example`, fill:

```env
INFISICAL_CLIENT_ID=
INFISICAL_CLIENT_SECRET=
INFISICAL_PROJECT_ID=
INFISICAL_SITE_URL=
```

`INFISICAL_CLIENT_ID` and `INFISICAL_CLIENT_SECRET` come from an Infisical
Machine Identity with Universal Auth enabled.

The bundled Infisical config expects these secrets:

- `/db/pg`, environment `prod`: `PG_PASS`
- `/keys`, environment `prod`: `PRIVATE_KEY`

## Daily Runtime Operations

Run these commands from the runtime directory. They are the normal operator
interface: before changing anything, each prints the exact Compose command it
will call. Append `--dry-run` to preview without changing containers.

### Start everything (default)

Use this for a self-contained local runtime: infrastructure plus controller.

```sh
./bin/uns runtime start
./bin/uns runtime status
./bin/uns runtime logs
./bin/uns runtime stop
```

### Infrastructure only

Use this for local Postgres, Mosquitto, Caddy, and QuestDB without starting the
controller:

```sh
./bin/uns runtime start --mode infra
./bin/uns runtime status --mode infra
./bin/uns runtime logs --mode infra
./bin/uns runtime stop --mode infra
```

### Controller only

Use this when Postgres, MQTT, and the other infrastructure already exist
elsewhere. Make sure
`configs/uns-openhub-controller/config-example.json` points to those external
services, or use `config-infisical-example.json` if those values come from
Infisical.

```sh
./bin/uns runtime start --mode controller
./bin/uns runtime status --mode controller
./bin/uns runtime logs --mode controller
./bin/uns runtime stop --mode controller
```

`logs` also accepts one or more service names, for example:

```sh
./bin/uns runtime logs postgres mosquitto
./bin/uns runtime logs --mode controller uns-openhub-controller
```

## Useful Commands

Reconfigure the runtime:

```sh
./bin/uns init -i
```

Install a verified private runtime without Git from the public bootstrap:

```sh
uns-bootstrap install --dir "$HOME/uns-openhub-runtime"
```

Update an installed runtime without Git:

```sh
"$HOME/.local/bin/uns-bootstrap" upgrade
```

`uns-bootstrap upgrade` downloads and verifies the selected immutable Runtime
release, stops the current Compose project before renaming the runtime
directory, preserves `.env`, `.secrets`, `configs`, and
`infisical-rotator.env`, updates the managed `UNS_TAG` to the controller image
tag recorded by the selected Runtime, starts the new Runtime, and runs the
controller's ordered database-schema migrations before it reports success. If
the migration fails, the new Runtime is stopped, the command fails, and the
previous runtime directory remains available as a rollback backup.
Re-running the same Runtime version reconciles the managed image tag and runs
the schema migration without stopping the already-running stack or creating
another backup.
It never removes volumes. `uns runtime stop` also stops any retained upgrade
backup directory that matches the current runtime name, so an interrupted old
upgrade can be cleaned up from the current runtime. First update Bootstrap
itself by re-running the platform installer above when a newer Bootstrap
release is available.

Before creating an optional Git release tag, check version and release-index
consistency from the runtime repository root:

```sh
./scripts/check-release-version.sh <version>
```

The check is read-only. It never stages, commits, tags, pushes, or publishes
images.

### Advanced: Git checkout maintenance

`runtime sync` is only for a Runtime installed as a Git checkout. A Bootstrap
installation intentionally is not a Git checkout; update it with
`uns-bootstrap upgrade` instead.

Synchronize a public or private runtime repository into a separate checkout:

```sh
./bin/uns runtime sync \
  --repo https://github.com/uns-openhub/uns-openhub-runtime.git \
  --dir "$HOME/uns-openhub-runtime"
```

The CLI first tries existing Git access. The initial checkout is shallow so
historic binary blobs from older runtime revisions are not downloaded. If an
HTTPS repository still requires
authentication, it asks for a GitHub read-only token using a hidden prompt. The
token is passed through a temporary `GIT_ASKPASS` environment and is not stored
in the remote URL or Git configuration. The command refuses dirty, mismatched,
or non-fast-forward checkouts and verifies fetched runtime content before
moving the local branch.

On Windows, run `uns runtime sync` from an installed copy of `uns.exe` outside
the checkout being updated so Git does not need to replace the running binary.

Update the controller code in the running controller container from the
versioned GitHub Release:

```sh
./bin/uns controller update \
  --runtime-dir "$HOME/uns-openhub-runtime" \
  --tag latest
```

This replaces only the controller runtime files. It first upgrades the
database schema and restarts the PM2 process named `controller` only after the
schema upgrade succeeds. It does not recreate the container.

`latest` means the immutable version recorded in the verified runtime
checkout, not an unpinned controller-source branch. You can also use a specific
version or an explicit offline artifact:

```sh
./bin/uns controller update --tag 7.1.22
./bin/uns controller update \
  --artifact controller-runtime-<version>.tar.gz \
  --checksum controller-runtime-<version>.tar.gz.sha256 \
  --offline
```

`uns controller refresh` is a compatibility alias for this artifact-based
update. It no longer clones or builds controller source in the running
container. Release downloads are cached under `.cache/releases`; keep the
previous versioned artifact and checksum for offline rollback.

When running from an existing runtime checkout, the CLI also has a convenience
flag:

```sh
./bin/uns controller update --pull --tag latest
```

On Windows, prefer running `git pull` separately before:

```powershell
.\bin\uns.cmd controller update --tag latest
```

Git may not be able to replace the currently running `uns-*.exe`.

Create an admin user after infrastructure is running. The command starts a
temporary controller tool container; the long-running controller service does
not need to be running. Omit `--password` to enter and confirm it in a hidden
prompt:

```sh
./bin/uns admin create --email admin@example.com --rules '#'
```

Reset an admin password:

```sh
./bin/uns admin reset --email admin@example.com
```

For unattended use, provide `UNS_ADMIN_PASSWORD` through the host's secret
mechanism. The explicit `--password` flag remains available for compatibility,
but can expose the value in shell history.

Generate keys:

```sh
./bin/uns gen-keys --kid key-2025-11 --activate
./bin/uns gen-keys --kid service-2025-11 --kind service --activate
```

Key generation uses temporary controller tool containers and does not require
the long-running controller service to be started.

For Podman on SELinux hosts, set this in `.env`:

```env
BIND_MOUNT_LABEL=,z
```

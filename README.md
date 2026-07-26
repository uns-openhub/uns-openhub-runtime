# UNS DataHub Controller Bundle (Registry)

> **Private initial release.** This generated repository is currently private.
> It may be made public later, but public visibility does not change the
> proprietary license or expose the private `uns-datahub-tools` source.

This bundle runs the UNS DataHub Controller from registry images. It supports
three common cases:

- start only the local infrastructure
- start only the controller
- start both local infrastructure and controller

## Setup

You need Docker or Podman with Compose, plus access to the registry images
configured in `.env`. The examples use `docker compose`; with Podman use
`podman compose` with the same arguments.

### Fresh install without Git or GitHub CLI

The public `uns-datahub-bootstrap` release contains only a minimal Go
downloader and installers. This runtime repository and its release assets may
remain private. macOS and Linux users start without Git, GitHub CLI, Node,
Python, or `jq`:

```sh
curl -fsSL \
  https://github.com/uns-datahub/uns-datahub-bootstrap/releases/latest/download/install.sh |
  sh

"$HOME/.local/bin/uns-bootstrap" install
```

The installer verifies and installs `uns-bootstrap` under `~/.local/bin`.
It first tries the matching runtime release anonymously. If the runtime is
private, it asks for a GitHub token using a hidden prompt and uses it only for
the release API requests; the token is not stored. Use a fine-grained,
expiring token limited to `uns-datahub-runtime` with read-only Contents
permission.

The bootstrap verifies the immutable offline runtime bundle, refuses a
non-empty destination, extracts it without links or path traversal, verifies
the matching private `uns` CLI, and starts that CLI's init wizard.

Windows PowerShell:

```powershell
Invoke-WebRequest `
  https://github.com/uns-datahub/uns-datahub-bootstrap/releases/latest/download/install.ps1 `
  -OutFile install.ps1
.\install.ps1
& "$HOME\.local\bin\uns-bootstrap.exe" install
```

Use `uns-bootstrap install --version <version>` for an immutable older release
or `uns-bootstrap install --offline <bundle.tar.gz>` with its sibling
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
prints the exact `docker compose` or `podman compose` commands to run next.

Manual setup:

1. Copy the environment template:

```sh
cp .env.example .env
```

2. Edit `.env` and set at least:

```env
UNS_REGISTRY=docker.io
UNS_REPO_PREFIX=unsdatahub
UNS_CONTROLLER_REPOSITORY=uns-datahub-controller
UNS_POSTGRES_REPOSITORY=uns-postgres
UNS_TAG=latest
CONFIG_FILE=config-example.json
```

These defaults resolve to:

```text
docker.io/unsdatahub/uns-datahub-controller:<version-or-latest>
docker.io/unsdatahub/uns-postgres:<version-or-latest>
```

Authenticate each host before pulling the private controller image:

```sh
podman login -u unsdatahub docker.io
```

Use `docker login` instead when running Docker. The Postgres repository is
public and does not require authentication. If an existing `.env` still has
`UNS_IMAGE_REPOSITORY`, replace it with `UNS_CONTROLLER_REPOSITORY` and
`UNS_POSTGRES_REPOSITORY` as shown above. The Compose files retain safe
defaults so regeneration does not overwrite the preserved `.env`.

3. For local runs without Infisical, keep `CONFIG_FILE=config-example.json`.
   This config reads optional Azure and OpenAI values from `.env`:

```env
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
AZURE_SCOPE=
AZURE_TENANT_ID=
OPENAI_KEY=
```

Leave them empty if you do not use those integrations. The default local
Postgres password is read from `POSTGRES_PASSWORD` in `.env`. If you change
`POSTGRES_USER` or `POSTGRES_DB`, update the same values in
`configs/uns-datahub-controller/config-example.json`.

4. Edit the controller config only when your endpoints differ from the local
   defaults:

```text
configs/uns-datahub-controller/config-example.json
```

If you create another config file, set `CONFIG_FILE` in `.env` to that file
name.

### Optional: Infisical

Use Infisical only if you want the controller config to resolve secrets from
Infisical instead of `.env`.

1. Set this in `.env`:

```env
CONFIG_FILE=config-infisical-example.json
```

2. Edit `configs/uns-datahub-controller/config-infisical-example.json` and
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
- `/azure`, environment `dev`: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SCOPE`, `AZURE_TENANT_ID`
- `/keys`, environment `prod`: `PRIVATE_KEY`
- `/openai`, environment `prod`: `AV_OPENAI_KEY`

## 1. Start Infra Only

Use this when you only need local Postgres, Mosquitto, Caddy, and QuestDB.

```sh
docker compose --env-file .env -f docker-compose.infra.yml up -d
```

Check status:

```sh
docker compose -f docker-compose.infra.yml ps
```

View logs one service at a time:

```sh
docker compose -f docker-compose.infra.yml logs -f postgres
docker compose -f docker-compose.infra.yml logs -f mosquitto
docker compose -f docker-compose.infra.yml logs -f caddy
docker compose -f docker-compose.infra.yml logs -f questdb
```

Stop:

```sh
docker compose -f docker-compose.infra.yml down
```

## 2. Start Controller Only

Use this when Postgres, MQTT, and other infrastructure already exist elsewhere.
Make sure `configs/uns-datahub-controller/config-example.json` points to those
external services, or use `config-infisical-example.json` if those values come
from Infisical.

```sh
docker compose --env-file .env -f docker-compose.controller.yml up -d
```

Check status:

```sh
docker compose -f docker-compose.controller.yml ps
```

View controller logs:

```sh
docker compose -f docker-compose.controller.yml logs -f uns-datahub-controller
```

Stop:

```sh
docker compose -f docker-compose.controller.yml down
```

## 3. Start Everything

Use this for a self-contained local runtime: infra plus controller.

```sh
docker compose --env-file .env up -d
```

Check status:

```sh
docker compose ps
```

View logs one service at a time:

```sh
docker compose logs -f postgres
docker compose logs -f mosquitto
docker compose logs -f caddy
docker compose logs -f questdb
docker compose logs -f uns-datahub-controller
```

Stop:

```sh
docker compose down
```

## Useful Commands

Reconfigure the runtime:

```sh
./bin/uns init -i
```

Install a verified private runtime without Git from the public bootstrap:

```sh
uns-bootstrap install --dir "$HOME/uns-datahub-runtime"
```

Before creating an optional Git release tag, check version and release-index
consistency from the runtime repository root:

```sh
./scripts/check-release-version.sh <version>
```

The check is read-only. It never stages, commits, tags, pushes, or publishes
images.

Synchronize a public or private runtime repository into a separate checkout:

```sh
./bin/uns runtime sync \
  --repo https://github.com/uns-datahub/uns-datahub-runtime.git \
  --dir "$HOME/uns-datahub-runtime-github"
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
  --runtime-dir "$HOME/uns-datahub-runtime-github" \
  --tag latest
```

This replaces only the controller runtime files and restarts the PM2 process
named `controller`. It does not recreate the container and does not replace RTT
node apps.

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

Create an admin user after the controller is running:

```sh
./bin/uns admin create --email admin@example.com --password 'strongpass' --rules '#'
```

Reset an admin password:

```sh
./bin/uns admin reset --email admin@example.com --password 'newpass'
```

Generate keys:

```sh
./bin/uns gen-keys --kid key-2025-11 --activate
./bin/uns gen-keys --kid service-2025-11 --kind service --activate
```

For Podman on SELinux hosts, set this in `.env`:

```env
BIND_MOUNT_LABEL=,z
```

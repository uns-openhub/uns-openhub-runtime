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

You need either Docker with Docker Compose, or Podman with Quadlet on Linux,
plus access to the registry images configured in `.env`. Docker deployments
use the generated Compose files. Podman production deployments use generated
Quadlet units and do not require a Compose provider.

Run the commands from the runtime bundle directory. When you need the bundled
CLI, use `./bin/uns` on macOS/Linux or `.\bin\uns.cmd` in Windows PowerShell.

Recommended setup:

```sh
./bin/uns init -i
```

The wizard creates or updates `.env`, prepares local or Infisical settings, and
prints Docker Compose or Podman Quadlet commands for the selected engine.

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

## Podman Production with Quadlet

Render reviewable Quadlet files with concrete image coordinates, absolute bind
paths, and configured Podman network/volume names:

```sh
./bin/uns quadlet render --runtime-dir "$PWD"
```

The rendered files contain no copied secret values. They reference `.env` and
`.secrets` in the runtime checkout. Before migrating an existing Podman
deployment, inspect `podman volume ls` and set the corresponding
`UNS_*_VOLUME` values in `.env`; otherwise a correctly named but empty volume
could be created.

After review, install the units without starting them:

```sh
sudo ./bin/uns quadlet install \
  --runtime-dir "$PWD" \
  --scope system \
  --mode both
```

The installer refuses changed managed files unless `--force` is explicit, and
keeps timestamped backups when replacing them. It prints the exact `systemctl`
commands for the selected mode. `--lite` omits QuestDB. Use `--scope user` for
a deliberately rootless deployment.

`quadlet install` never stops Compose containers, enables services, pulls
images, or starts containers. Stop the old deployment and verify its volume
mapping before executing the printed `systemctl enable --now` command.

## Docker Compose: Start Infra Only

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

## Docker Compose: Start Controller Only

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

## Docker Compose: Start Everything

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

Review a generated release and print the safe image/commit/tag sequence:

```sh
./scripts/release-checklist.sh
```

The checklist is read-only. It never stages, commits, tags, pushes, or
publishes images. Run all `./scripts/...` commands from the runtime repository
root. `./scripts/check-release-version.sh <version>` is also read-only: it only
checks version/artifact consistency before you decide whether to create a Git
tag.

Synchronize a public or private runtime repository into a separate checkout:

```sh
./bin/uns runtime sync \
  --repo https://github.com/uns-datahub/uns-datahub-runtime.git \
  --dir "$HOME/uns-datahub-runtime-github"
```

The CLI first tries existing Git access. If an HTTPS repository still requires
authentication, it asks for a GitHub read-only token using a hidden prompt. The
token is passed through a temporary `GIT_ASKPASS` environment and is not stored
in the remote URL or Git configuration. The command refuses dirty, mismatched,
or non-fast-forward checkouts and verifies fetched runtime content before
moving the local branch.

On Windows, run `uns runtime sync` from an installed copy of `uns.exe` outside
the checkout being updated so Git does not need to replace the running binary.

Update the controller code in the running controller container from that
verified checkout:

```sh
./bin/uns controller update \
  --runtime-dir "$HOME/uns-datahub-runtime-github" \
  --tag latest
```

This replaces only the controller runtime files and restarts the PM2 process
named `controller`. It does not recreate the container and does not replace RTT
node apps.

You can also use a specific version or an explicit artifact:

```sh
./bin/uns controller update --tag 7.1.22
./bin/uns controller update \
  --runtime-dir "$HOME/uns-datahub-runtime-github" \
  --artifact artifacts/controller-runtime/controller-runtime-<version>.tar.gz \
  --checksum artifacts/controller-runtime/controller-runtime-<version>.tar.gz.sha256
```

`uns controller refresh` is a compatibility alias for this artifact-based
update. It no longer clones or builds the controller source in the running
container. Keep the previous versioned artifact and checksum for offline
rollback.

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

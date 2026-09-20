#!/usr/bin/env bash
set -euo pipefail

version="$(tr -d '[:space:]' < VERSION)"
image_tag="$(tr -d '[:space:]' < release/image-tag)"
release_manifest="release/manifest.json"
checksum_index="release/SHA256SUMS"

python3 - "$version" "$image_tag" <<'PY'
import json
import re
import sys
from pathlib import Path

version = sys.argv[1]
image_tag = sys.argv[2]
paths = list(Path("configs").rglob("*.json"))
paths.append(Path("release/manifest.json"))
for path in paths:
    with path.open(encoding="utf-8") as handle:
        json.load(handle)

manifest = json.loads(Path("release/manifest.json").read_text(encoding="utf-8"))
if manifest.get("schemaVersion") != 2:
    raise SystemExit("Unsupported release manifest schema")
if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", str(manifest.get("product", ""))):
    raise SystemExit("Release manifest product must use lowercase kebab-case")
release_epoch = manifest.get("releaseEpoch")
if not isinstance(release_epoch, int) or isinstance(release_epoch, bool) or release_epoch < 1:
    raise SystemExit("Release manifest releaseEpoch must be a positive integer")
if manifest.get("version") != version or manifest.get("tag") != version:
    raise SystemExit("Release manifest version/tag does not match VERSION")
if manifest.get("imageTag") != image_tag:
    raise SystemExit("Release manifest imageTag does not match release/image-tag")
repository = manifest.get("repository", "")
if not re.fullmatch(r"[^/\s]+/[^/\s]+", repository):
    raise SystemExit("Release repository must use owner/repo form")
assets = manifest.get("assets")
if not isinstance(assets, list) or not assets:
    raise SystemExit("Release manifest has no assets")
names = [asset.get("name") for asset in assets]
if len(names) != len(set(names)):
    raise SystemExit("Release manifest contains duplicate assets")
for asset in assets:
    if not re.fullmatch(r"[0-9a-f]{64}", str(asset.get("sha256", ""))):
        raise SystemExit(f"Invalid asset checksum: {asset}")

controller = manifest.get("controller", {})
if controller.get("version") != image_tag:
    raise SystemExit("Controller artifact version does not match image tag")
if controller.get("packageVersion") != controller.get("version"):
    raise SystemExit("Controller artifact package version does not match controller provenance")
if not controller.get("source", {}).get("commit") or not controller.get("createdAt"):
    raise SystemExit("Controller provenance is incomplete")
print(f"Validated {len(paths)} JSON files and {len(assets)} release assets.")
PY

[[ "$(tr -d '[:space:]' < release/tag)" == "$version" ]] || {
  echo "release/tag does not match VERSION" >&2
  exit 1
}
[[ "$(tr -d '[:space:]' < release/repository)" == \
  "$(python3 -c 'import json; print(json.load(open("release/manifest.json"))["repository"])')" ]] || {
  echo "release/repository does not match release manifest" >&2
  exit 1
}
bootstrap_repository="$(
  tr -d '[:space:]' <release/bootstrap-repository
)"
[[ "$bootstrap_repository" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || {
  echo "release/bootstrap-repository must use owner/repo form" >&2
  exit 1
}
[[ -s "$checksum_index" ]] || {
  echo "Missing release checksum index: $checksum_index" >&2
  exit 1
}

expected_assets="$(
  python3 - <<'PY'
import json
for asset in json.load(open("release/manifest.json"))["assets"]:
    print(f'{asset["sha256"]}  {asset["name"]}')
PY
)"
[[ "$(cat "$checksum_index")" == "$expected_assets" ]] || {
  echo "release/SHA256SUMS does not match release manifest" >&2
  exit 1
}

grep -Fx 'UNS_REGISTRY=docker.io' .env.example
grep -Fx 'UNS_REPO_PREFIX=unsopenhub' .env.example
grep -Fx 'UNS_CONTROLLER_REPOSITORY=uns-openhub-controller' .env.example
grep -Fx 'UNS_POSTGRES_REPOSITORY=uns-postgres' .env.example
grep -Fx "UNS_TAG=$image_tag" .env.example
grep -F 'image: ${UNS_REGISTRY:-docker.io}/${UNS_REPO_PREFIX:-unsopenhub}/${UNS_CONTROLLER_REPOSITORY:-uns-openhub-controller}:${UNS_TAG:-latest}' \
  docker-compose.controller.yml docker-compose.yml
grep -F 'image: ${UNS_REGISTRY:-docker.io}/${UNS_REPO_PREFIX:-unsopenhub}/${UNS_POSTGRES_REPOSITORY:-uns-postgres}:${UNS_TAG:-latest}' \
  docker-compose.infra.yml docker-compose.yml
grep -F './runtime-tools:/opt/uns-runtime-tools:ro${BIND_MOUNT_LABEL:-}' \
  docker-compose.controller.yml docker-compose.yml

if grep -R -E 'fra\.ocir\.io|fricdwfcid28' \
  -- .env.example docker-compose.controller.yml docker-compose.infra.yml docker-compose.yml; then
  echo "Generated runtime still contains an OCIR-specific default." >&2
  exit 1
fi

bash -n \
  bin/uns \
  bin/uns-backup-helper \
  bin/infisical-rotator \
  bin/runtime-download \
  scripts/check-release-version.sh \
  scripts/verify-release-assets.sh

for file in \
  bin/uns \
  bin/uns-backup-helper \
  bin/infisical-rotator \
  bin/runtime-download \
  bin/uns.cmd \
  bin/uns-backup-helper.cmd \
  bin/infisical-rotator.cmd \
  bin/runtime-download.ps1; do
  [[ -s "$file" ]] || {
    echo "Missing runtime bootstrap file: $file" >&2
    exit 1
  }
done

[[ -s docs/controller-only-host-reconciliation.md ]] || {
  echo "Missing controller-only host reconciliation runbook" >&2
  exit 1
}
[[ -s docs/data-protection-and-recovery-policy.md ]] || {
  echo "Missing data protection and recovery policy" >&2
  exit 1
}
grep -F '## Environment runbook template' \
  docs/data-protection-and-recovery-policy.md >/dev/null || {
  echo "Data protection policy is missing the environment runbook boundary" >&2
  exit 1
}
[[ -s docs/recovery-key-custody.md ]] || {
  echo "Missing recovery key custody guide" >&2
  exit 1
}
grep -F 'PRIVATE_CLUSTER_CONFIG_KEY' \
  docs/controller-only-host-reconciliation.md >/dev/null || {
  echo "Controller reconciliation runbook is missing the dedicated cluster signer boundary" >&2
  exit 1
}
grep -F 'runtime start --mode controller --engine podman' \
  docs/controller-only-host-reconciliation.md >/dev/null || {
  echo "Controller reconciliation runbook is missing the controller-only lifecycle command" >&2
  exit 1
}
grep -F 'RTT inventory acceptance' \
  docs/controller-only-host-reconciliation.md >/dev/null || {
  echo "Controller reconciliation runbook is missing the RTT inventory acceptance gate" >&2
  exit 1
}
grep -F 'environment backup rtt-verify' \
  docs/controller-only-host-reconciliation.md >/dev/null || {
  echo "Controller reconciliation runbook is missing verified RTT backup recovery" >&2
  exit 1
}

for expected in \
  'PROCESSOR_ARCHITEW6432' \
  'PROCESSOR_ARCHITECTURE' \
  '"AMD64" { $GoArch = "amd64" }' \
  '"ARM64" { $GoArch = "arm64" }'; do
  grep -F "$expected" bin/runtime-download.ps1 >/dev/null || {
    echo "Runtime Windows downloader is missing architecture support: $expected" >&2
    exit 1
  }
done

if find bin -maxdepth 1 -type f \
  \( -name 'uns-*-amd64*' -o -name 'uns-*-arm64*' \
     -o -name 'uns-backup-helper-*-amd64*' \
     -o -name 'uns-backup-helper-*-arm64*' \
     -o -name 'infisical-rotator-*-amd64*' \
     -o -name 'infisical-rotator-*-arm64*' \) -print -quit |
  grep -q .; then
  echo "Platform binaries must be release assets, not runtime Git files." >&2
  exit 1
fi
if [[ -e artifacts/controller-runtime ]]; then
  echo "Controller tarballs must be release assets, not runtime Git files." >&2
  exit 1
fi

if [[ -d ".release/$version" ]]; then
  bash scripts/verify-release-assets.sh .
fi

echo "Runtime source ${version} is internally consistent."

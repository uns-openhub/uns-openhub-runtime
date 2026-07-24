#!/usr/bin/env bash
set -euo pipefail

version="$(tr -d '[:space:]' < VERSION)"
artifact_dir="artifacts/controller-runtime"
versioned_artifact="${artifact_dir}/controller-runtime-${version}.tar.gz"
latest_artifact="${artifact_dir}/controller-runtime-latest.tar.gz"

python3 - <<'PY'
import json
from pathlib import Path

paths = list(Path("configs").rglob("*.json"))
paths += list(Path("artifacts/controller-runtime").glob("*.manifest.json"))
for path in paths:
    with path.open(encoding="utf-8") as handle:
        json.load(handle)
print(f"Validated {len(paths)} JSON files.")
PY

if command -v sha256sum >/dev/null 2>&1; then
  for checksum in "${artifact_dir}"/*.sha256; do
    (cd "$artifact_dir" && sha256sum --check "$(basename "$checksum")")
  done
elif command -v shasum >/dev/null 2>&1; then
  for checksum in "${artifact_dir}"/*.sha256; do
    (cd "$artifact_dir" && shasum -a 256 --check "$(basename "$checksum")")
  done
else
  echo "sha256sum or shasum is required." >&2
  exit 127
fi

[[ -f "$versioned_artifact" ]] || {
  echo "Missing current runtime artifact: $versioned_artifact" >&2
  exit 1
}

cmp "$versioned_artifact" "$latest_artifact"

allowed_artifacts="
controller-runtime-${version}.manifest.json
controller-runtime-${version}.tar.gz
controller-runtime-${version}.tar.gz.sha256
controller-runtime-latest.tar.gz
controller-runtime-latest.tar.gz.sha256
"
while IFS= read -r artifact_path; do
  artifact_name="$(basename "$artifact_path")"
  if ! printf '%s' "$allowed_artifacts" | grep -Fxq "$artifact_name"; then
    echo "Unexpected stale controller runtime artifact: $artifact_path" >&2
    exit 1
  fi
done < <(find "$artifact_dir" -maxdepth 1 -type f -name 'controller-runtime-*' -print)

grep -Fx 'UNS_REGISTRY=docker.io' .env.example
grep -Fx 'UNS_REPO_PREFIX=unsdatahub' .env.example
grep -Fx 'UNS_CONTROLLER_REPOSITORY=uns-datahub-controller' .env.example
grep -Fx 'UNS_POSTGRES_REPOSITORY=uns-postgres' .env.example
grep -F 'image: ${UNS_REGISTRY:-docker.io}/${UNS_REPO_PREFIX:-unsdatahub}/${UNS_CONTROLLER_REPOSITORY:-uns-datahub-controller}:${UNS_TAG:-latest}' \
  docker-compose.controller.yml docker-compose.yml
grep -F 'image: ${UNS_REGISTRY:-docker.io}/${UNS_REPO_PREFIX:-unsdatahub}/${UNS_POSTGRES_REPOSITORY:-uns-postgres}:${UNS_TAG:-latest}' \
  docker-compose.infra.yml docker-compose.yml

if grep -R -E 'fra\.ocir\.io|fricdwfcid28' \
  -- .env.example docker-compose.controller.yml docker-compose.infra.yml docker-compose.yml; then
  echo "Generated runtime still contains an OCIR-specific default." >&2
  exit 1
fi

bash -n bin/uns bin/infisical-rotator scripts/release-checklist.sh

[[ -x scripts/release-checklist.sh ]] || {
  echo "Runtime release checklist is not executable." >&2
  exit 1
}

for file in \
  bin/uns-linux-amd64 \
  bin/uns-linux-arm64 \
  bin/uns-darwin-amd64 \
  bin/uns-darwin-arm64 \
  bin/uns-windows-amd64.exe \
  bin/uns-windows-arm64.exe \
  bin/infisical-rotator-linux-amd64 \
  bin/infisical-rotator-linux-arm64 \
  bin/infisical-rotator-darwin-amd64 \
  bin/infisical-rotator-darwin-arm64 \
  bin/infisical-rotator-windows-amd64.exe \
  bin/infisical-rotator-windows-arm64.exe; do
  [[ -s "$file" ]] || {
    echo "Missing or empty runtime binary: $file" >&2
    exit 1
  }
done

for template in \
  quadlet/templates/uns-datahub.network.tmpl \
  quadlet/templates/uns-pgdata.volume.tmpl \
  quadlet/templates/uns-postgres.container.tmpl \
  quadlet/templates/uns-mosquitto.container.tmpl \
  quadlet/templates/uns-caddy.container.tmpl \
  quadlet/templates/uns-questdb.container.tmpl \
  quadlet/templates/uns-controller.container.tmpl; do
  [[ -s "$template" ]] || {
    echo "Missing or empty Quadlet template: $template" >&2
    exit 1
  }
done

quadlet_tmp="$(mktemp -d)"
trap 'rm -rf "$quadlet_tmp"' EXIT
./bin/uns quadlet render \
  --runtime-dir "$PWD" \
  --env-file .env.example \
  --output "$quadlet_tmp"

[[ "$(find "$quadlet_tmp" -maxdepth 1 -type f \( -name '*.container' -o -name '*.volume' -o -name '*.network' \) | wc -l | tr -d '[:space:]')" = "11" ]]
grep -Fx 'Image=docker.io/unsdatahub/uns-datahub-controller:latest' "$quadlet_tmp/uns-controller.container"
grep -Fx 'Image=docker.io/unsdatahub/uns-postgres:latest' "$quadlet_tmp/uns-postgres.container"
grep -Fx 'VolumeName=pgdata' "$quadlet_tmp/uns-pgdata.volume"
if grep -R -F 'change-me' "$quadlet_tmp"; then
  echo "Rendered Quadlet files contain a copied secret value." >&2
  exit 1
fi

echo "Runtime bundle ${version} is internally consistent."

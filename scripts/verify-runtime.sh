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
bash -n bin/uns bin/infisical-rotator

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

echo "Runtime bundle ${version} is internally consistent."

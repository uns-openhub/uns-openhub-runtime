#!/usr/bin/env bash
set -euo pipefail

runtime_dir="${1:-.}"
version="$(tr -d '[:space:]' < "$runtime_dir/VERSION")"
asset_dir="$runtime_dir/.release/$version"
checksum_index="$runtime_dir/release/SHA256SUMS"

[[ -d "$asset_dir" ]] || {
  echo "Local release assets not found: $asset_dir" >&2
  exit 2
}
[[ -s "$checksum_index" ]] || {
  echo "Release checksum index not found: $checksum_index" >&2
  exit 2
}

verify_checksum() {
  local expected="$1"
  local path="$2"
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$path" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  else
    echo "sha256sum or shasum is required" >&2
    exit 127
  fi
  [[ "$actual" == "$expected" ]] || {
    echo "SHA-256 mismatch for $path" >&2
    exit 1
  }
}

while read -r expected asset_name extra; do
  [[ -n "$expected" && -n "$asset_name" && -z "${extra:-}" ]] || {
    echo "Invalid release checksum entry: $expected $asset_name ${extra:-}" >&2
    exit 1
  }
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid SHA-256 value for $asset_name" >&2
    exit 1
  }
  [[ "$asset_name" != */* && "$asset_name" != *".."* ]] || {
    echo "Unsafe release asset name: $asset_name" >&2
    exit 1
  }
  [[ -s "$asset_dir/$asset_name" ]] || {
    echo "Missing release asset: $asset_dir/$asset_name" >&2
    exit 1
  }
  verify_checksum "$expected" "$asset_dir/$asset_name"
done <"$checksum_index"

offline_name="uns-datahub-runtime-${version}-offline.tar.gz"
[[ -s "$asset_dir/$offline_name" ]] || {
  echo "Missing offline runtime bundle: $asset_dir/$offline_name" >&2
  exit 1
}
read -r offline_sha offline_file <"$asset_dir/$offline_name.sha256"
[[ "$offline_file" == "$offline_name" ]] || {
  echo "Offline checksum references unexpected file: $offline_file" >&2
  exit 1
}
verify_checksum "$offline_sha" "$asset_dir/$offline_name"

echo "Runtime release assets $version are internally consistent."

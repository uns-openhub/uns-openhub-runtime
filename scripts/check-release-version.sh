#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
version="$(tr -d '[:space:]' < VERSION)"

if [[ -z "$tag" ]]; then
  echo "Usage: $0 <release-tag>" >&2
  exit 2
fi

if [[ "$tag" != "$version" ]]; then
  echo "Release tag '$tag' does not match VERSION '$version'." >&2
  exit 1
fi

for suffix in manifest.json tar.gz tar.gz.sha256; do
  path="artifacts/controller-runtime/controller-runtime-${version}.${suffix}"
  [[ -f "$path" ]] || {
    echo "Missing release artifact: $path" >&2
    exit 1
  }
done

[[ -f "artifacts/controller-runtime/controller-runtime-latest.tar.gz.sha256" ]] || {
  echo "Missing latest runtime checksum." >&2
  exit 1
}

echo "Release tag '$tag' matches runtime bundle '$version'."

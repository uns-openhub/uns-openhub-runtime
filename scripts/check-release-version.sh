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
[[ "$(tr -d '[:space:]' < release/tag)" == "$version" ]] || {
  echo "release/tag does not match VERSION." >&2
  exit 1
}
python3 - "$version" <<'PY'
import json
import sys

version = sys.argv[1]
manifest = json.load(open("release/manifest.json"))
if manifest.get("version") != version or manifest.get("tag") != version:
    raise SystemExit("Release manifest does not match VERSION")
if not manifest.get("assets"):
    raise SystemExit("Release manifest has no assets")
PY

echo "Release tag '$tag' matches runtime source and release index '$version'."

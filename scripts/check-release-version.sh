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
bootstrap_repository="$(
  tr -d '[:space:]' <release/bootstrap-repository
)"
[[ "$bootstrap_repository" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || {
  echo "release/bootstrap-repository must use owner/repo form." >&2
  exit 1
}
python3 - "$version" <<'PY'
import json
import re
import sys

version = sys.argv[1]
manifest = json.load(open("release/manifest.json"))
if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", str(manifest.get("product", ""))):
    raise SystemExit("Release manifest has no valid product identity")
release_epoch = manifest.get("releaseEpoch")
if not isinstance(release_epoch, int) or isinstance(release_epoch, bool) or release_epoch < 1:
    raise SystemExit("Release manifest has no valid release epoch")
if manifest.get("version") != version or manifest.get("tag") != version:
    raise SystemExit("Release manifest does not match VERSION")
if not manifest.get("assets"):
    raise SystemExit("Release manifest has no assets")
PY

echo "Release tag '$tag' matches runtime source and release index '$version'."

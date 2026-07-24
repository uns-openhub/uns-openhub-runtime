#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release-checklist.sh [--skip-verify]

Runs read-only release checks and prints the recommended image/runtime release
sequence. It never stages, commits, tags, pushes, or publishes anything.
EOF
}

skip_verify=false
case "${1:-}" in
  "")
    ;;
  --skip-verify)
    skip_verify=true
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runtime_dir="$(cd "$script_dir/.." && pwd)"
cd "$runtime_dir"

version="$(tr -d '[:space:]' < VERSION)"
[[ -n "$version" ]] || {
  echo "VERSION is empty." >&2
  exit 1
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "Release checklist requires a Git checkout." >&2
  exit 1
}

registry="${UNS_REGISTRY:-docker.io}"
repo_prefix="${UNS_REPO_PREFIX:-unsdatahub}"
controller_repository="${UNS_CONTROLLER_REPOSITORY:-uns-datahub-controller}"
postgres_repository="${UNS_POSTGRES_REPOSITORY:-uns-postgres}"
if command -v podman >/dev/null 2>&1; then
  container_cmd=podman
else
  container_cmd=docker
fi

if [[ "$skip_verify" != true ]]; then
  echo "== Verifying runtime ${version} =="
  bash scripts/verify-runtime.sh
  echo
fi

git diff --check

branch="$(git branch --show-current)"
remote="$(git remote get-url origin 2>/dev/null || true)"
status="$(git status --short)"

echo "== Runtime release status =="
echo "Version: ${version}"
echo "Branch: ${branch:-detached HEAD}"
echo "Remote: ${remote:-not configured}"
echo

if [[ -z "$status" ]]; then
  echo "Worktree is clean; there is no generated release diff to publish."
else
  echo "Generated changes:"
  printf '%s\n' "$status"
  echo
  echo "Tracked diff summary:"
  git diff --stat
  untracked="$(git ls-files --others --exclude-standard)"
  if [[ -n "$untracked" ]]; then
    echo
    echo "Untracked release files:"
    printf '%s\n' "$untracked"
  fi
fi

cat <<EOF

== Recommended next steps ==

1. Review the runtime diff (read-only):
   git status --short
   git diff --check
   git diff --stat

2. From uns-datahub-tools, inspect the exact image destinations:
   make print-release-plan VERSION=${version}

3. After explicit publish approval, publish and then verify both images:
   make release-runtime VERSION=${version} PUBLISH=true
   make release-runtime-postgres VERSION=${version} PUBLISH=true
   ${container_cmd} manifest inspect ${registry}/${repo_prefix}/${controller_repository}:${version}
   ${container_cmd} manifest inspect ${registry}/${repo_prefix}/${postgres_repository}:${version}

4. Only after both versioned images are reachable, stage and review this
   generated runtime release:
   git add -A
   git diff --cached --check
   git diff --cached --stat
   git commit -m "Release runtime ${version}"
   git push origin ${branch:-main}

5. Optional, only when a Git release tag is explicitly approved:
   bash scripts/check-release-version.sh ${version}
   git tag ${version}
   git push origin ${version}

No stage, commit, tag, push, or image publish action was performed.
EOF

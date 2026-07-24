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
printf -v runtime_dir_q '%q' "$runtime_dir"
printf -v branch_q '%q' "${branch:-main}"

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

   Continue only when both manifest commands exit successfully.

4. Publish the generated runtime repository.

   Run the following commands in the runtime checkout:
   cd ${runtime_dir_q}

   First review every generated addition, modification, and deletion:
   git status --short
   git diff --check
   git diff --stat

   If that list is expected, stage the complete generated release. "Stage"
   means preparing these files for one Git commit; it does not push anything:
   git add -A
   git diff --cached --check
   git diff --cached --name-status
   git diff --cached --stat

   If the staged list is not correct, unstage it without deleting local files:
   git restore --staged .

   If the staged list is correct, create and push the runtime commit:
   git commit -m "Release runtime ${version}"
   git push origin ${branch_q}
   git status --short

   The final status should be empty. At this point runtime main contains the
   new release and operators can pull it.

5. Decide whether to create a formal Git release tag.

   Stop after step 4 if you only want to update runtime main.

   For a formal immutable release matching the published image version, first
   check that the tag does not already exist. If "git tag --list" prints the
   version, do not recreate or move it:
   git fetch --tags origin
   git tag --list ${version}

   The next script is read-only. It only checks that VERSION, the requested
   tag, artifacts, and checksums agree; it does not create or push a tag:
   ./scripts/check-release-version.sh ${version}

   Only after that check succeeds, create and push the tag:
   git tag -a ${version} -m "UNS DataHub runtime ${version}"
   git push origin ${version}

   Pushing the tag triggers the runtime repository's release validation
   workflow. It does not rebuild or publish the Docker images.

No stage, commit, tag, push, or image publish action was performed.
EOF

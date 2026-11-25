#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_dir=$(dirname "$script_dir")
backup_root=""
dsmc=/opt/tivoli/tsm/client/ba/bin/dsmc
retention_mode=plan
apply=false

usage() {
  cat <<'EOF'
Usage: install-recovery-retention-systemd.sh --backup-root <absolute path> [options]

Previews installation by default. Set retention rules in Recovery first. Pass --apply to
install the service and timer, and enable the timer. The installed timer defaults
to non-destructive plan mode.

Options:
  --runtime-dir <path>              Installed Runtime root
  --backup-root <path>              Recovery backup root (required)
  --dsmc <path>                     IBM Storage Protect client
  --retention-mode <plan|apply>     Daily mode (default: plan)
  --apply                           Install and enable the timer
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runtime-dir) runtime_dir=${2-}; shift 2 ;;
    --backup-root) backup_root=${2-}; shift 2 ;;
    --dsmc) dsmc=${2-}; shift 2 ;;
    --retention-mode) retention_mode=${2-}; shift 2 ;;
    --apply) apply=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$runtime_dir" in /*) ;; *) echo "--runtime-dir must be absolute" >&2; exit 2 ;; esac
case "$backup_root" in /*) ;; *) echo "--backup-root must be absolute" >&2; exit 2 ;; esac
case "$dsmc" in /*) ;; *) echo "--dsmc must be absolute" >&2; exit 2 ;; esac
case "$retention_mode" in plan|apply) ;; *) echo "--retention-mode must be plan or apply" >&2; exit 2 ;; esac
[ -x "$runtime_dir/bin/uns" ] || { echo "Runtime CLI is not executable: $runtime_dir/bin/uns" >&2; exit 2; }
[ -d "$backup_root" ] || { echo "Backup root does not exist: $backup_root" >&2; exit 2; }
[ -x "$dsmc" ] || { echo "IBM Storage Protect client is not executable: $dsmc" >&2; exit 2; }
[ -f "$runtime_dir/systemd/uns-recovery-retention.service" ] || { echo "Runtime retention service template is missing" >&2; exit 2; }
[ -f "$runtime_dir/systemd/uns-recovery-retention.timer" ] || { echo "Runtime retention timer template is missing" >&2; exit 2; }

cat <<EOF
UNS recovery retention installation plan
  Runtime:             $runtime_dir
  Backup root:         $backup_root
  TSM client:          $dsmc
  Daily mode:          $retention_mode
  Timer:               daily at 06:30 local time, with up to 15 minutes jitter
EOF

if [ "$apply" != true ]; then
  echo "Preview only. Re-run with --apply to install the plan-mode timer."
  exit 0
fi
[ "$(id -u)" -eq 0 ] || { echo "--apply must run as root" >&2; exit 2; }

for value in "$runtime_dir" "$backup_root" "$dsmc"; do
  case "$value" in *[!a-zA-Z0-9_./-]*) echo "Unsupported character in installation path" >&2; exit 2 ;; esac
done

"$runtime_dir/bin/uns" environment backup doctor --mounted-policy --root "$backup_root" --dsmc "$dsmc"

unit_tmp=$(mktemp /etc/systemd/system/.uns-retention.XXXXXX)
trap 'rm -f "$unit_tmp"' EXIT HUP INT TERM
sed -e "s|@RUNTIME_DIR@|$runtime_dir|g" -e "s|@BACKUP_ROOT@|$backup_root|g" -e "s|@MODE@|$retention_mode|g" -e "s|@DSMC@|$dsmc|g" "$runtime_dir/systemd/uns-recovery-retention.service" > "$unit_tmp"
chmod 644 "$unit_tmp"
mv "$unit_tmp" /etc/systemd/system/uns-recovery-retention.service
install -m 644 "$runtime_dir/systemd/uns-recovery-retention.timer" /etc/systemd/system/uns-recovery-retention.timer
systemctl daemon-reload
systemctl enable --now uns-recovery-retention.timer

echo "Installed retention timer in $retention_mode mode."
echo "Check readiness: $runtime_dir/bin/uns environment backup doctor --root $backup_root --dsmc $dsmc"
echo "Inspect timer: systemctl list-timers uns-recovery-retention.timer"

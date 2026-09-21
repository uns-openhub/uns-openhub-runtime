#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
runtime_dir=$(dirname "$script_dir")
backup_root=""
dsmc=/opt/tivoli/tsm/client/ba/bin/dsmc
minimum_age_days=30
keep_latest=3
max_filespace_age_hours=36
retention_mode=plan
apply=false

usage() {
  cat <<'EOF'
Usage: install-recovery-retention-systemd.sh --backup-root <absolute path> [options]

Previews installation by default. Pass --apply to write /etc/uns/recovery-retention.env,
install the service and timer, and enable the timer. The installed timer defaults
to non-destructive plan mode.

Options:
  --runtime-dir <path>              Installed Runtime root
  --backup-root <path>              Recovery backup root (required)
  --dsmc <path>                     IBM Storage Protect client
  --minimum-age-days <days>         At least 30 (default: 30)
  --keep-latest <count>             Recovery groups always kept (default: 3)
  --max-filespace-age-hours <hours> TSM freshness limit (default: 36)
  --retention-mode <plan|apply>     Daily mode (default: plan)
  --apply                           Install and enable the timer
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --runtime-dir) runtime_dir=${2-}; shift 2 ;;
    --backup-root) backup_root=${2-}; shift 2 ;;
    --dsmc) dsmc=${2-}; shift 2 ;;
    --minimum-age-days) minimum_age_days=${2-}; shift 2 ;;
    --keep-latest) keep_latest=${2-}; shift 2 ;;
    --max-filespace-age-hours) max_filespace_age_hours=${2-}; shift 2 ;;
    --retention-mode) retention_mode=${2-}; shift 2 ;;
    --apply) apply=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$runtime_dir" in /*) ;; *) echo "--runtime-dir must be absolute" >&2; exit 2 ;; esac
case "$backup_root" in /*) ;; *) echo "--backup-root must be absolute" >&2; exit 2 ;; esac
case "$dsmc" in /*) ;; *) echo "--dsmc must be absolute" >&2; exit 2 ;; esac
case "$minimum_age_days" in *[!0-9]*|'') echo "--minimum-age-days must be an integer" >&2; exit 2 ;; esac
case "$keep_latest" in *[!0-9]*|'') echo "--keep-latest must be an integer" >&2; exit 2 ;; esac
case "$max_filespace_age_hours" in *[!0-9]*|'') echo "--max-filespace-age-hours must be an integer" >&2; exit 2 ;; esac
[ "$minimum_age_days" -ge 30 ] || { echo "--minimum-age-days must be at least 30" >&2; exit 2; }
[ "$keep_latest" -ge 1 ] || { echo "--keep-latest must be at least 1" >&2; exit 2; }
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
  Minimum local age:   $minimum_age_days days
  Keep latest:         $keep_latest groups
  TSM freshness limit: $max_filespace_age_hours hours
  Timer:               daily at 06:30 local time, with up to 15 minutes jitter
EOF

if [ "$apply" != true ]; then
  echo "Preview only. Re-run with --apply to install the plan-mode timer."
  exit 0
fi
[ "$(id -u)" -eq 0 ] || { echo "--apply must run as root" >&2; exit 2; }

for value in "$runtime_dir" "$backup_root" "$dsmc"; do
  case "$value" in *'"'*|*'\'*|*' '*|*'	'*|*'
'*) echo "Paths containing whitespace, quotes, or backslashes are not supported in the systemd environment" >&2; exit 2 ;; esac
done

"$runtime_dir/bin/uns" environment backup doctor \
  --root "$backup_root" \
  --minimum-age-days "$minimum_age_days" \
  --keep-latest "$keep_latest" \
  --max-filespace-age-hours "$max_filespace_age_hours" \
  --dsmc "$dsmc"

install -d -m 700 /etc/uns
env_tmp=$(mktemp /etc/uns/recovery-retention.env.XXXXXX)
trap 'rm -f "$env_tmp"' EXIT HUP INT TERM
cat >"$env_tmp" <<EOF
UNS_RUNTIME_DIR=$runtime_dir
UNS_BACKUP_ROOT=$backup_root
UNS_RETENTION_MODE=$retention_mode
UNS_RETENTION_MINIMUM_AGE_DAYS=$minimum_age_days
UNS_RETENTION_KEEP_LATEST=$keep_latest
UNS_TSM_DSMC=$dsmc
UNS_TSM_MAX_FILESPACE_AGE_HOURS=$max_filespace_age_hours
EOF
chmod 600 "$env_tmp"
mv "$env_tmp" /etc/uns/recovery-retention.env
trap - EXIT HUP INT TERM
install -m 644 "$runtime_dir/systemd/uns-recovery-retention.service" /etc/systemd/system/uns-recovery-retention.service
install -m 644 "$runtime_dir/systemd/uns-recovery-retention.timer" /etc/systemd/system/uns-recovery-retention.timer
systemctl daemon-reload
systemctl enable --now uns-recovery-retention.timer

echo "Installed retention timer in $retention_mode mode."
echo "Check readiness: $runtime_dir/bin/uns environment backup doctor --root $backup_root --dsmc $dsmc"
echo "Inspect timer: systemctl list-timers uns-recovery-retention.timer"

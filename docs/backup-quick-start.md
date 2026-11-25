# Backup and retention quick start

This guide protects controller configuration, the PostgreSQL control plane,
RTT microservice deployment files, signed cluster configuration, and recovery
metadata. QuestDB history and other service-owned datasets require their own
database backup policy.

## Portable backups for a single Controller

An administrator can open **Recovery → Portable backups** and select **Create backup**.
To automate the same capture, enable **Daily backup**, choose a time and time zone,
and select **Save schedule**. A restart after the scheduled time catches up once for
that local date. Each completed archive is a single `openhub-*.zip` in the host
directory bound to `/var/lib/uns-backups` (`UNS_BACKUP_DIR`). It can be copied to
tape and later returned to the same mount with its original filename. Access to
the ZIP grants access to the database dump and configurations, so use a private
folder and trusted copies. Restrict filesystem write access to the owner.

**Restore one service on a running Controller.** Put the archive in the target
backup folder, select **Refresh archives**, expand the file and choose
**Restore instance…** next to the desired service. Confirm the restore, review
the stopped configuration and start the instance from **Micro services**.
The selection restores the service configuration and saved configuration versions.
The target keeps its database and running instances. A conflicting instance ID
or process name blocks the import. Catalog packages require access to their
matching immutable release. Archived Node packages require access to the
dependencies pinned in their pnpm lockfile.

**Restore the full control plane.** Install a fresh single-controller Runtime
with the Controller version recorded in the archive and the same PostgreSQL
major version. Start its infrastructure and keep its Controller stopped.
From the installed Runtime directory, pass the ZIP's basename:

```sh
./scripts/restore-portable-backup.sh openhub-<archive-id>.zip
```

After a successful command, start the Controller normally. The command restores
PostgreSQL and the local services, generates new signing identities and keeps the
target installation's network and database connection settings. If the initial
database already has tables, it restores into a new database on that server.
After a file publication failure, fix the reported target mount and repeat the
command with the same archive before starting the Controller.

This format covers independent local Node/pnpm microservices. It omits
`node_modules`, pending queues and QuestDB history. External secret providers
must still be reachable with the target installation's credentials.

## Mounted retention policy

In Recovery, expand **Retention policy**, enter the minimum local age, number of newer groups to keep and maximum age of external backup evidence, then save. Check the acknowledgement from each controller. The resulting `recovery-policy.json` lives directly in each bound backup directory and can be included in external backups. Only these numeric rules and the format version travel with the archives. A fresh restore works without this file.

The optional host timer reads the mounted policy on each run. Its installation chooses the provider executable and plan or apply mode. External provider credentials remain with the provider. For an upgrade, save the rules and install the updated unit in plan mode. Review a fresh plan before retiring the old environment file or enabling automatic removal.

## What runs where

| Component | Responsibility | Recommended time |
|---|---|---|
| Controller master | Creates one application-consistent cluster recovery point | 21:00 |
| IBM Storage Protect | Copies each host's recovery directory off the host | Around 23:00 |
| Host retention timer | Verifies TSM evidence and plans or removes expired local groups | 06:30 |

Only the third step can remove local files, and a new installation starts in
read-only `plan` mode.

## First safe setup on a Linux host

Set the two host paths once. These examples match a normal `opc` installation;
change them when Runtime is installed under another account:

```sh
RUNTIME=/home/opc/uns-openhub-runtime
BACKUPS=/home/opc/uns-openhub-runtime-data/backups
```

Check TSM and the recovery directory without changing anything:

```sh
sudo "$RUNTIME/bin/uns" environment backup doctor \
  --root "$BACKUPS" \
  --dsmc /opt/tivoli/tsm/client/ba/bin/dsmc
```

Run this check with the same account as the retention service. The packaged
systemd service uses `root`, which can read a root-owned `dsm.sys` and the
generated TSM password file.

Preview the timer installation, then repeat with `--apply` when the displayed
paths are correct:

```sh
sudo "$RUNTIME/scripts/install-recovery-retention-systemd.sh" \
  --runtime-dir "$RUNTIME" \
  --backup-root "$BACKUPS"

sudo "$RUNTIME/scripts/install-recovery-retention-systemd.sh" \
  --runtime-dir "$RUNTIME" \
  --backup-root "$BACKUPS" \
  --apply
```

Confirm the timer. It now creates plans and does not delete recovery groups:

```sh
systemctl list-timers uns-recovery-retention.timer
systemctl cat uns-recovery-retention.service
```

The safe daily order is:

1. the current controller master creates one cluster recovery point;
2. the external backup provider copies each host's local recovery root;
3. local retention plans or removes only old recovery groups already verified
   in the external provider.

## 1. Configure the controller schedule

Use the same node-local schedule on every controller that may become master.
Only the current master starts the job, and the shared job ledger prevents a
duplicate for the same local calendar day.

```json
{
  "recovery": {
    "backup": {
      "enabled": true,
      "maxDurationSeconds": 3600,
      "schedule": {
        "enabled": true,
        "dailyAt": "21:00",
        "timeZone": "Europe/Ljubljana"
      }
    }
  }
}
```

Restart controllers one at a time after changing node-local configuration.
Keep the active master until the other members are healthy, then perform the
final handover or restart.

## 2. Verify IBM Storage Protect

Install and authenticate the IBM Storage Protect client before configuring
retention. `dsmcad` must be active and the server must assign a daily
incremental schedule after the controller recovery window.

```sh
systemctl is-enabled dsmcad
systemctl is-active dsmcad
/opt/tivoli/tsm/client/ba/bin/dsmc query schedule
/opt/tivoli/tsm/client/ba/bin/dsmc query filespace -dateformat=5 -timeformat=1
```

For a 21:00 controller recovery, a TSM start near 23:00 leaves a clear capture
window. Use include/exclude rules that contain the full recovery root.

## 3. Run the read-only doctor

```sh
./bin/uns environment backup doctor \
  --root /absolute/runtime-data/backups \
  --dsmc /opt/tivoli/tsm/client/ba/bin/dsmc
```

Doctor changes no data. It blocks readiness when the recovery root or TSM
client is unavailable, the matching filespace has no recent successful
incremental, or a retention run lock needs review. Add `--json` for automation.

## 4. Install daily plan mode

The packaged installer in this section targets Linux hosts managed by systemd.
Other operating systems can run the same `retention-run --mode plan` command
from their native scheduler.

Preview first:

```sh
sudo ./scripts/install-recovery-retention-systemd.sh \
  --backup-root /absolute/runtime-data/backups
```

Install only after reviewing the paths:

```sh
sudo ./scripts/install-recovery-retention-systemd.sh \
  --backup-root /absolute/runtime-data/backups \
  --apply
```

The timer runs near 06:30 local time and starts in `plan` mode. It creates a
private plan under `backups/.retention-audit/` but deletes nothing. It refuses
to run while a `dsmc` backup process is active or when the last successful TSM
incremental is older than 36 hours.

## 5. Approve local expiry after 30 days

The CLI enforces at least 30 local days and always protects the newest three
recovery job groups. Review the first eligible plan and apply it manually:

```sh
./bin/uns environment backup retention-plan \
  --root /absolute/runtime-data/backups \
  --minimum-age-days 30 \
  --keep-latest 3 \
  --output /secure/path/retention-plan.json

./bin/uns environment backup retention-apply \
  --plan /secure/path/retention-plan.json \
  --confirm-plan-sha256 sha256:<exact-plan-hash>
```

After one complete manual cycle succeeds, switch the installed timer to apply
mode by re-running the installer with both `--retention-mode apply` and
`--apply`. Automated apply repeats all filesystem and active TSM copy checks
before removing a complete UUID recovery group.

## 6. Verify operation

```sh
systemctl list-timers uns-recovery-retention.timer
journalctl -u uns-recovery-retention.service
find /absolute/runtime-data/backups/.retention-audit -maxdepth 1 -type f -print
```

Keep the age identity and private signing material outside replaceable Runtime
directories and include them in a separately controlled recovery escrow. Test
a representative restore at least twice per year and after material changes to
encryption, signing, storage, or controller topology.

## Troubleshooting a retained lock

An interrupted host process can leave `backups/.retention-run.lock`. Doctor
reports that condition and automated retention stops. First prove that no
`retention-run` or `dsmc` process is active and inspect the service journal.
Only then remove the empty lock directory with `rmdir`; the next timer run will
perform every preflight again. Never remove an artifact or staging directory to
clear a lock.

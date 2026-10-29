# Review physical storage before a Runtime change

Use this document with the CLI shipped in the same Runtime release. Physical
storage, running Controller version and complete data recovery are different
facts. The preflight is read-only: it never provisions state volumes, enables
queues, expands permissions or repairs labels.

From the Runtime directory, select the actual engine and review the current
image, mounted roots, numeric owner/mode and available space:

```sh
bin/uns runtime preflight --mode controller --engine podman
```

Use `docker` for a Docker installation. An offline image probe does not establish
the running Controller process version. A different backup filesystem does not
provide capacity for a state filesystem. Missing or unproved mounts block the
check; do not remove retained volumes to make it pass.

## Private capacity review

The inventory is an operator review, not automatic discovery or a reservation.
Include active, planned and retained configurations, including stopped instances
whose journals must remain. Prepare a mode-0600 JSON selection, for example:

```json
{
  "schemaVersion": 1,
  "coverage": {"active": true, "planned": true, "retained": true},
  "memoryReserveBytes": 268435456,
  "services": {
    "uns-openhub-controller": {
      "instances": [{
        "relative": "rtt-nodes/example-adapter/1.0.0/instances/example/config.json",
        "sha256": "REPLACE_WITH_THE_CONFIG_SHA256",
        "journalWorkingBytes": 16777216
      }],
      "additionalWorkingMemoryBytes": 134217728,
      "filesystemReserveBytes": 67108864
    }
  }
}
```

Replace the example path/digest and measured budgets. The displayed amounts are
illustrations, not production sizing advice. Use each actual Compose Controller
service as the map key. Configuration files must be standard installed files
beneath the code mount, private regular files, not symlinks, and at most 256 KiB.
Never copy configuration values into support output.

```sh
chmod 600 capacity-selection.json
bin/uns runtime capacity-plan --engine podman \
  --selection capacity-selection.json --output reviewed-capacity.json
bin/uns runtime preflight --mode controller --engine podman \
  --capacity-plan reviewed-capacity.json
```

The selected image's baked compatible shared SDK supplies resolved queue limits
and paths. The probe does not import application code, open queue databases or
contact brokers. Input-journal working overhead is explicit; MQTT outbox disk
limits already include SQLite/WAL/SHM. Disabled outboxes add no outbox capacity.
Shared exact journals count once, while conflicting limits block the review.
Disk maxima and working allowances are combined on each actual filesystem with
its reserve; memory includes SDK buffers, explicit application working headroom
and host reserve. Samples can change after the check.

Only after review, install the approved current-image plan as the private file
`runtime-capacity-plan.json`. Without a plan, capacity is explicitly unassessed.
For another image, create a separate target plan and keep the old plan intact:

```sh
bin/uns runtime capacity-plan --engine podman \
  --controller-image docker.io/example/controller:REVIEWED_TARGET_TAG \
  --selection capacity-selection.json --output next-image-capacity.json
uns-bootstrap upgrade --dir /path/to/runtime --version TARGET_RUNTIME_VERSION \
  --mode controller --engine podman \
  --capacity-plan /private/path/next-image-capacity.json
```

Bootstrap checks the staged target before stopping the working Runtime. The old
installation retains its own plan for rollback. A changed image, configuration
or limit requires a new review. An old program directory does not roll back
application database migrations.

## SELinux storage-owner procedure

For a rootless Podman installation, recursive `:z`/`:Z` relabeling may fail on
root-owned archive files. Keep SELinux enforcing and preserve file permissions.
The storage owner can review one narrow physical subtree using the bundled
helper and standard host tools `semanage`, `matchpathcon` and `getenforce`:

```sh
sudo install -d -m 0700 /root/openhub-storage-review
sudo python3 scripts/runtime-storage-label-policy.py plan \
  --root /srv/openhub/state/backups/system-logs \
  --output /root/openhub-storage-review/labels.json
sudo python3 scripts/runtime-storage-label-policy.py apply \
  --plan /root/openhub-storage-review/labels.json --sha256 REVIEWED_SHA256
```

Review the exact root, ownership/modes, proposed labels and printed plan digest
before apply. The helper refuses symlinks, hardlinked files, special files,
filesystem crossings and oversized trees; it does not read file bodies. Apply
adds only that escaped subtree's persistent `container_file_t:s0` rule and
reconciles interrupted work using the same unchanged reviewed plan.

A persistent rule does not automatically label future files. The owning archive
writer must run `restorecon -F -- EXACT_NEW_FILE` after creation/move. Review new
or changed trees separately. Only after storage-owner review, an explicitly empty
`UNS_BACKUP_BIND_LABEL` or `UNS_RECOVERY_BIND_LABEL` can avoid recursive engine
relabeling for that root; unset inherits `BIND_MOUNT_LABEL`. Other roots retain
their normal policy. The CLI generates the derived storage-label Compose file;
do not edit it by hand or globally turn off relabeling to bypass a failed check.

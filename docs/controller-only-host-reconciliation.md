# Controller-only host reconciliation

Use this procedure to replace an ad-hoc controller container or an older
Runtime checkout with a Bootstrap-managed, controller-only Runtime. Work on one
cluster member at a time. Keep the current master and at least one other member
healthy until the candidate has rejoined the cluster.

Before starting, verify that the environment's offline age identity is under
independent custody as described in
[`recovery-key-custody.md`](recovery-key-custody.md). Normal recovery points do
not contain that decryption key.

The procedure preserves operator-owned state. It does not copy a complete
`config.json` between hosts: controller identity, public base URL, paths, Caddy
ownership, and local secret-provider bootstrap remain node-local.

## State boundaries

Preserve these node-local values before changing the host:

- controller name and public base URL
- active controller configuration and its secret-provider references
- Infisical rotator bootstrap environment or token source
- setup state and controller crypto identity
- cached cluster profile and its trust public key
- recovery archives and the active controller volume
- the complete RTT deployment inventory, especially every active
  `instances/<id>/config.json`, configuration history, and
  `controller-state.json`
- current systemd units, container/image inventory, and SELinux labels

Keep these values common across every controller that can become master:

- the signed cluster configuration profile
- the cluster profile trust public key
- the private key used to sign a new cluster profile revision

Store the cluster signing key in a dedicated secret such as
`/keys:PRIVATE_CLUSTER_CONFIG_KEY`. Do not reuse a user JWT key or service JWT
key. Every eligible authoring controller should resolve its node-local
`configSync.signingPrivateKey` reference to the same dedicated secret.

Never print private keys, access tokens, `.env` contents, or files from
`crypto/keys`. Validate them by parse result, derived public-key fingerprint,
file mode, or checksum instead.

## 1. Capture a recovery point

Before stopping anything, record the effective installation and copy the state
needed to undo the cutover into a root-only directory outside the replaceable
Runtime checkout. At minimum capture:

```sh
umask 077
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
recovery_dir="/var/lib/uns/backups/host-reconcile-$stamp"
install -d -m 700 "$recovery_dir"

podman ps --all --no-trunc >"$recovery_dir/podman-ps.txt"
podman images --digests >"$recovery_dir/podman-images.txt"
podman volume ls >"$recovery_dir/podman-volumes.txt"
systemctl cat uns-controller-podman.service \
  >"$recovery_dir/uns-controller-podman.service.txt" 2>&1 || true
systemctl cat infisical-rotator.service \
  >"$recovery_dir/infisical-rotator.service.txt" 2>&1 || true
```

Copy configuration, unit files, and required persistent state without
dereferencing secrets into terminal output. Record checksums for the copied
tree. Retain the previous controller image and volume until the new controller
has survived a controlled restart and rejoined the cluster.

### RTT inventory acceptance

Controller-only mode controls which Compose services run; it does not mean the
controller's RTT filesystem may be empty. Before creating or selecting a new
`controller_code` volume, identify the mounted `rtt-nodes` root and record a
secret-free inventory of node, version, and instance identifiers. Count active
configuration and desired-state files without printing their contents:

```sh
rtt_root=<active-controller-volume-data>/rtt-nodes
find "$rtt_root" -path '*/instances/*/config.json' -type f | wc -l
find "$rtt_root" -path '*/instances/*/controller-state.json' -type f | wc -l
```

Create and verify a signed, age-encrypted RTT component before cutover. Keep
the age identity outside the Runtime and off the target host except during a
bounded restore operation:

```sh
./bin/uns environment backup rtt-create \
  --rtt-root "$rtt_root" \
  --controller <controller-name> \
  --output <new-component-directory> \
  --recipient <age1-recipient> \
  --signing-key <backup-signing-key.pem>

./bin/uns environment backup rtt-verify \
  --backup <component-directory> \
  --trusted-signer <backup-trusted-signer.pem> \
  --identity <age-identity.txt>
```

Record the expected installed nodes, versions, instance IDs, configuration
file count, and desired-running count from the active controller API. A
cutover is not accepted when a previously non-empty inventory becomes empty or
any expected active instance loses `configAvailable`. If repositories remain
available, application releases may be reinstalled, but the active instance
configuration and desired state must still come from the verified archive.
Never delete the previous volume or encrypted RTT component until this
comparison and a controlled restart both pass.

## 2. Install the Runtime beside the old installation

Install Bootstrap and the selected immutable Runtime release into the standard
per-user location:

```sh
curl -fsSL \
  https://github.com/uns-openhub/uns-openhub-bootstrap/releases/latest/download/install.sh |
  sh

"$HOME/.local/bin/uns-bootstrap" install --version <runtime-version>
cd "$HOME/uns-openhub-runtime"
./bin/uns version
./scripts/verify-runtime.sh
```

Do not delete or overwrite the old checkout during this step. Bootstrap keeps
backup storage outside the replaceable Runtime directory.

## 3. Restore only the required state

Create the host-specific controller configuration under
`configs/uns-openhub-controller/`. Use Infisical references for shared secrets
and keep local identity and routing values specific to this host.

Restore the following state to the new named volumes after checking ownership
and permissions expected by the image:

- controller setup state
- controller crypto identity
- cached cluster profile
- cluster profile trust public key

Do not replace the verified cluster trust public key with a different key. If
the host must author shared configuration, configure the dedicated Infisical
cluster-signing-key reference and verify that its derived public key matches the
installed trust public key before restart.

On SELinux hosts, do not mount a named-volume data directory into a transient
container with `:Z`. That can assign a private MCS category and make the real
Compose container fail with `EACCES`. Named-volume content should retain the
general container label, normally `system_u:object_r:container_file_t:s0`.
An atomic configuration replacement can also carry `admin_home_t` or another
host label into an otherwise correctly relabeled bind-mount directory. Before
restart, compare the active file with a readable sibling using `ls -Z` and use
`chcon --reference=<readable-sibling> <active-config>` when they differ.

## 4. Validate without taking the active controller down

Before cutover, validate the candidate configuration and secrets using an
isolated container or an unused local port. Confirm all of the following:

- the controller configuration parses
- the Infisical bootstrap files are readable only by the service account
- user and service signing keys load and produce the expected JWKS entries
- the cluster profile signature verifies
- the dedicated cluster signing key, when configured, matches the trust key
- the image architecture matches the host
- only the controller process will start for controller-only mode

Do not infer public readiness from the Caddy admin endpoint. Controller health,
cluster membership, master state, and the public proxy path are separate
checks.

## 5. Cut over one member

Stop the old controller only after the candidate has passed isolated
validation. Start the new Runtime in controller-only mode:

```sh
cd "$HOME/uns-openhub-runtime"
./bin/uns runtime start --mode controller --engine podman
```

Wait for container health and a stable `follower_ready` or `master_ready`
result. Confirm that PM2 contains only the controller process and that the
member appears online from the active master.

For a host that owned RTT microservices before reconciliation, restore the
verified RTT member or reinstall its reviewed releases and restore the archived
instance directories before declaring cutover complete. When publishing a
staged tree into a Podman named volume on SELinux, apply the same
`container_file_t` label used by readable sibling volume content before the
controller starts. A host label such as `user_home_t` causes `EACCES` while
scanning `rtt-nodes`, even when Unix ownership and mode look correct.

For boot persistence, install the exact Runtime CLI outside a root home
directory and point systemd at that executable. Some SELinux policies prohibit
systemd from executing scripts or binaries below `/root` even when the file
mode is correct. The service should call the Runtime lifecycle instead of
duplicating a raw `podman run` command:

```ini
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/root/uns-openhub-runtime
ExecStart=/usr/local/bin/uns-openhub-runtime runtime start --mode controller --engine podman
ExecStop=/usr/local/bin/uns-openhub-runtime runtime stop --mode controller --engine podman
```

Adapt `User`, `WorkingDirectory`, and the installed CLI path to the host. Verify
the installed CLI checksum against the matching Runtime release.

For rootless Podman managed by a system unit, set `User` and `Group` to the
operator account and provide its `HOME`, `XDG_RUNTIME_DIR`, and a `PATH` that
contains the Compose provider. Enable lingering for the account. Without those
values, systemd can invoke a different Podman storage or fail to discover
`podman-compose` even though the same command works in an interactive shell.

## 6. Repoint and verify the rotator

Keep the existing machine identity or rotator token source. Update the rotator
service so its output directory is the active Runtime's `.secrets` directory,
then restart it:

```sh
systemctl daemon-reload
systemctl restart infisical-rotator.service
systemctl is-active infisical-rotator.service
```

Verify that the secret files were refreshed, are owned by the expected account,
and have mode `0600`. Do not display their values.

## 7. Restart test and acceptance

Use a controlled service restart before deleting old artifacts:

```sh
systemctl restart uns-controller-podman.service
systemctl is-active uns-controller-podman.service
podman ps --filter label=io.podman.compose.project=uns-openhub-runtime
```

Acceptance requires evidence for all of these points:

- controller container is healthy after the restart
- controller reports the intended Runtime/image version
- cluster profile revision and signature are valid
- user and service JWKS keys are loaded
- controller rejoins with the expected name and public base URL
- PM2 has no infrastructure processes on a controller-only host
- the post-cutover RTT inventory matches the recorded node/version/instance
  inventory and every expected active instance has a readable configuration
- every expected desired-running RTT instance is online, or has an explicitly
  reviewed reason to remain stopped
- the rotator is enabled, active, and refreshing the active `.secrets`
- another cluster member remains available throughout the change
- a controller promoted to master can read the shared profile and, when it is
  an authoring master, resolve the shared cluster signing key

Only after acceptance should old checkouts, build caches, stale images, and
inactive large runtime-update backups be removed. Keep the rollback image,
volume, unit backups, and recovery point for the agreed retention period.

## Stabilize a connection storm

Rapid handovers or overlapping controller restarts can leave thousands of
short-lived connections around a rootless Podman port forward. Symptoms include
high `rootlessport` CPU, growing `LAST-ACK` or `TIME-WAIT` counts on port 3200,
health-check timeouts, and repeated elections even though the controller
process itself is running.

Do not continue promoting or restarting all members together. Stop the
non-master members, leave one healthy candidate running until it reaches
`master_ready` and rebuilds public routes, then start each follower separately.
Wait for each one to report `follower_ready` before starting the next. Confirm
that port-3200 connection counts and `rootlessport` CPU are falling before
resuming maintenance. Preserve the elected master until the cluster and public
proxy path have remained stable.

## Rollback

If the candidate cannot become healthy or rejoin the cluster, stop the new
Runtime, restore the previous unit and configuration, and recreate the old
container from the retained image and volumes. Re-check the original health and
cluster membership before investigating the candidate further. Do not reuse a
partially migrated volume as the rollback source.

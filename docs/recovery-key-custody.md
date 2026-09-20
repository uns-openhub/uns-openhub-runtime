# Recovery key custody

The Runtime encrypts controller configuration, PostgreSQL snapshots and RTT
deployment files for an age X25519 recipient. The matching
`age-identity.txt` is required to decrypt those recovery artifacts. Losing it
makes every artifact encrypted for that recipient unusable, even when the
artifact and its signature are otherwise valid.

Treat this identity as production break-glass material. It is not controller
runtime state and is deliberately excluded from normal recovery points.

## Separate runtime and recovery material

`uns environment backup keygen --output <new-directory>` creates two halves:

| Location | Files | Purpose |
|---|---|---|
| Controller secret storage | `age-recipient.txt`, `backup-signing-key.pem` | Encrypt and sign new recovery artifacts. |
| Offline recovery custody | `age-identity.txt`, `backup-trusted-signer.pem` | Decrypt and authenticate an artifact during recovery. |

The age recipient and trusted signer are public. The age identity and signing
key are private. Never print, log, commit, paste into a ticket, or place either
private file in an ordinary shared folder.

The controller may keep a Runtime-specific copy named
`backup-age-recipient.txt`. It must not keep `age-identity.txt`. A compromised
controller that holds both an encrypted backup and its decryption identity
does not provide an independent recovery boundary.

## Minimum custody policy

Keep at least two recoverable copies of the offline pair in independent
failure domains:

1. an owner-only operator copy on an encrypted workstation or in an operating
   system credential vault;
2. an encrypted offline copy on separate media or in a break-glass vault whose
   access does not depend on the UNS control plane.

The second copy must survive loss of the workstation, all controller hosts and
the normal secret provider. Infisical or another online vault may hold an
additional copy when its authentication and recovery path remain available
during a full UNS outage, but it must not be the only copy.

Directories containing private recovery material must be mode `0700` and
private files mode `0600`. Record the custodian, creation date, recipient
fingerprint and where each copy is held. Record only public fingerprints, not
private file contents.

## Verify a custody copy

Verification must prove that the stored identity derives the recipient used by
the Runtime, and that it can decrypt a retained artifact. Do this without
printing the identity:

```sh
umask 077
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT HUP INT TERM

age-keygen -y <offline-custody>/age-identity.txt >"$work/derived-recipient.txt"
cmp "$work/derived-recipient.txt" \
  <runtime>/.secrets/backup-age-recipient.txt

<runtime>/bin/uns environment backup rtt-verify \
  --backup <retained-rtt-component> \
  --trusted-signer <offline-custody>/backup-trusted-signer.pem \
  --identity <offline-custody>/age-identity.txt
```

Use the corresponding verify command for another component. A portable cluster
bundle can first be checked without decryption with
`cluster-recovery-bundle-verify`; the component-level check above additionally
proves that the custody identity can decrypt protected payloads. Verification
is read-only. Do not extract private payloads into a normal working directory.

For a macOS operator workstation, Login Keychain can provide a second local
vault copy. Add the value through standard input so it does not enter shell
history or the process argument list:

```sh
(cat <offline-custody>/age-identity.txt; \
 cat <offline-custody>/age-identity.txt) | \
security add-generic-password -U \
  -a <environment-name> \
  -s com.uns-openhub.recovery.age-identity \
  -l 'UNS OpenHub recovery age identity' \
  -j 'Break-glass recovery key; keep an independent offline copy' \
  -w
```

Keychain protects against accidental file deletion but does not replace the
independent offline copy.

## Rotation and retirement

Generating a new identity does not re-encrypt existing recovery artifacts.
Keep every old identity and its trusted signer until all artifacts encrypted
for that recipient have expired and been independently removed under the
retention policy. Label generations by environment and creation date; never
overwrite an old custody directory in place.

After any rotation, Runtime replacement or controller-host reconciliation:

1. compare the derived recipient with every controller's configured public
   recipient;
2. create a new cluster recovery point;
3. verify complete controller membership and RTT coverage;
4. verify decryption with the offline identity;
5. test access to the independent copy without relying on the UNS cluster.

Do not delete previous Runtime volumes or encrypted recovery points until
these checks pass and the new state has survived a controlled restart.

# Data protection and recovery policy

This policy defines the minimum protection and recovery controls for an UNS
OpenHub deployment. It is intentionally independent of a particular host,
storage vendor, network, or backup product. Environment-specific runbooks map
these controls to real paths, schedules, owners and recovery targets.

The objective is a recoverable service, not merely a successful file copy. A
backup is usable only when its complete component set, cryptographic trust,
decryption material and restore procedure have been verified together.

## Policy outcomes

Every production deployment must be able to answer these questions:

1. Which business services and data must be recovered?
2. How much data loss and downtime are acceptable for each service?
3. Which artifacts form one complete recovery point?
4. Where is an independent off-host copy held?
5. Who can decrypt, authenticate and restore it during a control-plane outage?
6. When was the latest representative restore test completed?

An operator must record explicit recovery point objectives (RPO), recovery
time objectives (RTO), retention and owners before selecting a schedule. A
default schedule without business-approved RPO and RTO is planning evidence,
not an approved protection level.

## Protection principles

- Keep at least three copies of required data, on at least two storage types,
  with at least one copy outside the Runtime failure domain and one copy that
  cannot be changed by a compromised Runtime administrator.
- Capture databases and application state through supported, application-aware
  mechanisms. A live filesystem copy of a database or container volume is not
  automatically consistent.
- Encrypt sensitive payloads before or during transfer, encrypt the backup
  store at rest, and authenticate recovery artifacts with pinned signing
  identities.
- Keep recovery decryption identities separate from the hosts and backup
  payloads they protect.
- Verify checksums, signatures, membership and declared omissions before an
  artifact is accepted or copied off-host.
- Test restoration in an isolated target. Monitoring backup creation alone
  does not prove recoverability.
- Remove expired recovery material through a recorded retention process. Key
  generations remain available until every artifact encrypted for them has
  expired.

## Data classes and required controls

| Class | Examples | Required protection |
| --- | --- | --- |
| Control plane | Controller database, shared profile, reviewed configuration and audit state | Application-consistent encrypted recovery point; off-host copy; regular restore test |
| Runtime deployment | Version manifest, local configuration, installed RTT services and their instance configuration | Versioned recovery component or reproducible release plus preserved configuration; capture before and after material change |
| Business and history data | QuestDB history, service-owned databases, files and externally managed datasets | Native database backup, snapshot or replication policy with its own RPO, retention and integrity test |
| Service identities | Active controller and service signing keys | Dedicated signed and encrypted identity escrow; restricted custody and restore procedure |
| Recovery identities | Decryption identity and trusted signer used to verify recovery artifacts | Two independent break-glass copies outside the Runtime; never stored beside the ordinary backup payload as its only copy |
| Secret-provider bootstrap | Provider token, project identity, endpoint and rotation bootstrap | Restricted backup or independently reproducible enrollment procedure; no secret values in ordinary manifests or logs |
| Reproducible material | Container images, release archives and package dependencies | Preserve immutable version and digest evidence; mirror artifacts when the recovery objective cannot depend on an external registry |
| Caches and transient state | Image layers, build caches, staging directories and temporary restore work | Exclude unless a documented recovery requirement proves otherwise |

Each recovery manifest must state what it includes and omits. QuestDB or a
service-owned database is not protected merely because the controller recovery
point is complete.

## Recovery-point composition

A cluster recovery point should bind the following evidence under one opaque
identifier:

- the control-plane capture from exactly one designated coordinator;
- the signed shared configuration profile when one is active;
- one configuration and RTT deployment contribution for every frozen cluster
  member;
- expected membership and exact component checksums;
- Runtime, controller, helper, operating-system and architecture identities;
- creation, completion and verification timestamps;
- explicit omissions and any degraded or partial state.

A distributed recovery set may retain member payloads on their source hosts.
That is useful for local recovery but is not an independent disaster-recovery
copy. The backup system must collect the parent manifest and every bound member
component into the same external protection domain, or preserve an equivalent
mapping that can reproduce the complete set without any source host.

The collected copy must preserve file names, permissions, symbolic-link
metadata, manifests and checksums exactly. Backup software must not transform
encrypted artifacts, normalize line endings or follow archived symbolic links.

## Capture and transfer procedure

1. Freeze or record the expected cluster membership and component ownership.
2. Create the supported application-consistent recovery point.
3. Wait for a terminal successful state. Reject an incomplete, membership-
   partial or unverified set.
4. Verify signatures and checksums at the source without extracting protected
   payloads into a shared working directory.
5. Transfer the complete set to the approved external backup system over an
   authenticated, encrypted channel.
6. Verify the destination copy independently and record its immutable object,
   generation or backup identifier.
7. Confirm that the recovery identity and trusted signer are available through
   the separate break-glass process.
8. Record RPO age, retention class, operator or automation identity and result.

For continuously changing database volumes, first create a native logical or
physical backup, storage snapshot, or other database-supported consistent
capture. Configure file-oriented backup software to collect that completed
artifact. Copying a live database directory is allowed only when its database
and storage documentation explicitly support the selected snapshot method.

## When to capture

The approved environment runbook must define a schedule that satisfies the
business RPO. In addition, create and export a recovery point:

- before and after a Runtime, controller or database-schema upgrade;
- after cluster membership, shared configuration or trust-key changes;
- after installing, removing or materially reconfiguring a service;
- after recovery-key or service-identity rotation;
- before decommissioning a host or storage location;
- immediately after a successful restore or major incident repair.

A reasonable initial baseline for an environment without stricter business
requirements is one daily recovery point, one additional point before material
change, 30 daily generations and 12 monthly generations. This baseline must be
replaced when the approved RPO, regulation or data volume requires another
schedule.

## Encryption and key custody

Ordinary recovery artifacts are encrypted for an offline recovery recipient
and signed by the producing environment. The Runtime may hold the public
recipient and the private signing material required to create artifacts. It
must not retain the only copy of the matching recovery decryption identity.

Keep at least two recoverable copies of the offline recovery pair in independent
failure domains. One may be an encrypted operator workstation or credential
vault. The other must survive loss of that workstation, all Runtime hosts and
the normal secret provider. Record only public fingerprints in inventories,
tickets and monitoring.

Service signing identities require a separate identity-escrow artifact. A raw
copy of the live cryptographic volume contains private keys and is acceptable
only inside an approved encrypted backup boundary with restricted access and a
consistency mechanism. Prefer the dedicated signed and encrypted escrow format.

Rotation creates a new generation; it does not make old encrypted artifacts
decryptable with the new identity. Retain old recovery identities until every
dependent artifact has expired and deletion has been independently confirmed.

See [Recovery key custody](recovery-key-custody.md) for the concrete key split,
permissions and read-only verification procedure.

## Retention, immutability and deletion

The environment owner must define daily, monthly and incident-retention
classes. At least one external generation should be immutable or protected by
backup-system controls that Runtime credentials cannot disable.

Do not expire the last verified recovery point for a supported software line,
the last pre-upgrade point, or an artifact that is under incident, legal or
audit hold. Do not delete an old key generation while retained artifacts still
depend on it.

Deletion must remove all declared copies, update the inventory and preserve an
audit record containing the artifact identifier, public checksum, retention
rule, time and approving identity. The audit record must not contain decrypted
payloads or private key material.

## Restore validation

Perform a representative restore rehearsal at least twice per year and after a
material change to backup format, key custody, storage provider or recovery
workflow. Systems with stricter RTO or regulatory requirements need a shorter
interval.

The rehearsal must:

1. start from the external copy rather than a convenient source-host copy;
2. verify the bundle, signatures, membership and checksums before decryption;
3. obtain recovery identities through the documented break-glass process;
4. restore into an isolated, fenced target with no production publishing or
   external side effects;
5. verify database integrity, configuration, service inventory and a bounded
   business data sample;
6. measure achieved RPO and RTO;
7. destroy or formally retain the test target under the same data-handling
   rules;
8. record findings, owners and remediation deadlines.

A syntax check, archive listing, successful checksum, controller startup or
single health endpoint is not by itself a restore rehearsal.

## Monitoring and evidence

Monitor at least:

- age of the newest complete recovery point and newest external copy;
- missing cluster members or components;
- checksum, signature, encryption or transfer failures;
- backup-store capacity and retention failures;
- pending key rotation or missing custody verification;
- date and result of the latest restore rehearsal.

Alerts must identify the affected protection class and required operator
action without exposing secret values. Backup success, external-copy success
and restore-test success are distinct states.

## Environment runbook template

Create one private runbook per environment containing:

- service owner, backup owner and recovery approver;
- approved RPO, RTO, schedule and retention per data class;
- exact source and external storage locations;
- supported capture, verify, publish and restore commands for the installed
  Runtime version;
- database-native protection procedures for every business datastore;
- recovery and service-identity custody locations expressed by vault or asset
  identifier, never by private value;
- network fencing, DNS, routing and failover steps;
- monitoring destinations and escalation contacts;
- date, evidence and findings of the latest restore rehearsal.

Host names, passwords, tokens, private paths and environment-specific
credentials belong only in this restricted runbook or the relevant secret
provider. They do not belong in the general policy or public documentation.

## Public documentation boundary

Public guidance derived from this policy should explain how to classify data,
set RPO and RTO, create a complete recovery point, copy it off-host, separate
key custody and test a restore. It may show generic placeholders and link to
version-matched Runtime commands.

Public guidance must not publish environment paths, internal host names,
retention exceptions, storage credentials, private fingerprints, incident
details or commands whose contract is not part of a released Runtime. The
installed Runtime README remains authoritative for version-specific command
syntax.

# RFC 0019: Ledger segments and snapshots

|            |                                                                                   |
| ---------- | --------------------------------------------------------------------------------- |
| RFC        | 0019                                                                              |
| Status     | Draft                                                                             |
| Author     | Zin Nam                                                                           |
| Created    | 2026-11-26                                                                        |
| Affects    | `ledger-1`, proposed by RFC 0014: objects and checks added. Nothing else changes. |
| Supersedes | Nothing                                                                           |

Three objects for `ledger-1` ledgers that grow without end: a **segment**, a range of entries kept as one content-addressed object that can sit in cold storage; a **snapshot**, the replay state at a checkpoint, signed by the writer and cosigned by witnesses that replayed to it; and the **archive list**, which says where every earlier entry went, deleted ones included. A relying party then verifies from a snapshot instead of from the genesis, and anyone holding the segments checks the snapshot by replay. No entry, checkpoint or existing outcome changes. It builds on RFC 0014 ([#57](https://github.com/dekrops/wvp/pull/57)) and answers its open question 2. Its number assumes it is the next pull request after #61; the pull request fixes it (RFC 0001, section 5). This RFC proposes the design for review. It does not publish it.

## Motivation

In a throughput test of a hosted gate, one tenant's ledger grew by about 12 KB per gated action. At about 0.35 actions per second, that is roughly 0.4 GB a day and 130 GB a year, per tenant.

Storing that costs little. Verifying it does not. RFC 0014 verifies a ledger by replaying it from the genesis: every entry is checked against the state after those before it, so verification is linear in the ledger's length, and a relying party that checks a year of that ledger checks every signature in 130 GB. Nor does a relying party need every entry of last year online to act on today's state.

| #   | Need                                              | Missing in `ledger-1`                                                                 |
| --- | ------------------------------------------------- | ------------------------------------------------------------------------------------- |
| S1  | Verify a long ledger without replaying all of it  | A state to start from, and a way to check it                                          |
| S2  | Keep old entries off line, and fetch them on need | A unit of archive, named so that what comes back is shown to be what was stored       |
| S3  | Start at a recent position                        | The record state before it: RFC 0014's open question 2 leaves it, and unique contents |
| S4  | Delete history at the end of a retention period   | A way to tell deletion from loss, and either from a writer hiding entries             |

Checkpoints do not answer S1. A checkpoint commits to a history, not to the state it gives: knowing the root at size _n_, a verifier still replays _n_ entries to learn who may sign entry _n_.

Snapshots of replicated state are common practice; transparency logs ([RFC 9162](https://www.rfc-editor.org/rfc/rfc9162)) commit to history and not to a state. This RFC adds the state, bound to the history.

## What changes

`ledger-1` gains three objects, a signing domain for the snapshot and one for its cosignature, and two verification modes beside the one RFC 0014 defines. Every object is in `verified-json-v1`, with digests as `{ "algorithm": "sha-256", "hex" }` and signatures as `{ "scheme", "keyId", "encoded" }`, as RFC 0014 spells them. Positions and sizes are as RFC 0014's: the state at position _p_ is the fold of entries 0 to _p_ − 1, and a checkpoint of size _n_ covers entries 0 to _n_ − 1.

### 1. Segments

A **segment** is a contiguous range of signed entries that ends where the writer signed a checkpoint, with the tree state it starts from:

```json
{
  "protocol": "ledger-1",
  "ledger": { "algorithm": "sha-256", "hex": "…" },
  "start": 1048576,
  "size": 2097152,
  "frontier": [{ "algorithm": "sha-256", "hex": "…" }],
  "entries": [{ "entry": { "…": "…" }, "signatures": ["…"] }]
}
```

- `entries` are the signed entries at positions `start` to `size` − 1, exactly as RFC 0014 defines them, in order. There is at least one.
- `frontier` is the **frontier** at `start`: the RFC 9162 hashes of the largest complete subtrees that cover leaves 0 to `start` − 1, one for each bit set in `start`, the largest first. It is empty when `start` is 0, and has at most 64 hashes.
- The **segment digest** is SHA-256 of the canonical segment. It names the segment wherever it is stored or listed.

**A segment checks against roots, not against its storage.** Folding `frontier` from the right gives the tree root at `start`. Appending the leaves of `entries` (RFC 0014, section 7) to `frontier` and folding gives the root at `size`, which must be that checkpoint's root. The frontier a segment ends with is the next segment's. So a run of segments from 0 reproduces every root it passes, and one segment is checked against two roots without the entries before it. The digest only finds the object; the roots prove what it is.

Signature octets are in the segment digest but not in a leaf (RFC 0014, section 7). Two copies of one range that differ in an ECDSA signature's form have the same roots and different digests. The copy the archive list names is the one kept.

A segment is not claim registration v1's log segment, which is a run of receipts. It is a range of a `ledger-1` ledger with the tree state it starts from.

### 2. Snapshots

A **snapshot** is the state a verifier has after replaying a ledger to a checkpoint, in canonical parts named by digest, and signed by the writer:

```json
{
  "snapshot": {
    "protocol": "ledger-1",
    "ledger": { "algorithm": "sha-256", "hex": "…" },
    "size": 2097152,
    "root": { "algorithm": "sha-256", "hex": "…" },
    "last": { "algorithm": "sha-256", "hex": "…" },
    "basis": { "algorithm": "sha-256", "hex": "…" },
    "core": {
      "trust": { "algorithm": "sha-256", "hex": "…" },
      "approvals": { "algorithm": "sha-256", "hex": "…" },
      "requests": { "algorithm": "sha-256", "hex": "…" },
      "contents": { "algorithm": "sha-256", "hex": "…" }
    },
    "extensions": [
      {
        "id": "gate",
        "format": "…",
        "digest": { "algorithm": "sha-256", "hex": "…" }
      }
    ],
    "segments": { "algorithm": "sha-256", "hex": "…" },
    "previous": { "algorithm": "sha-256", "hex": "…" },
    "issuedAt": "2026-11-26T10:00:00Z"
  },
  "signature": { "scheme": "Ed25519", "keyId": "…", "encoded": "…" }
}
```

| Member       | Meaning                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------- |
| `size`       | The size of a checkpoint the writer signed. The snapshot is the state at position `size` |
| `root`       | That checkpoint's root                                                                   |
| `last`       | The entry digest at `size` − 1, as in the checkpoint                                     |
| `basis`      | The trust basis in force at `size`: the entry digest of the latest trust entry before it |
| `core`       | The digest of each core part (below)                                                     |
| `extensions` | The state parts of extensions (below), ascending by `id`. Possibly empty                 |
| `segments`   | The digest of the archive list at this snapshot (section 5)                              |
| `previous`   | The snapshot digest of the writer's previous snapshot of this ledger, or `null`          |
| `issuedAt`   | When the writer says it signed it. No rule reads it                                      |

It is signed over `verified:ledger-snapshot:v1\n` followed by the canonical `snapshot`, by the writer in force at entry `size` − 1, as a checkpoint is. The **snapshot digest** is SHA-256 of the canonical `snapshot`. A snapshot is an object beside the ledger. It is never an entry: the writer signs no entry (RFC 0014, section 6).

**The core parts.** Each part is an object with `protocol` `ledger-1`, `part` its name, and the members below. Its digest is SHA-256 of its canonical text. Every array is in the order given, without duplicates. Each value is spelled as the entries spell it: keys as a trust registry does, references as RFC 0014, section 9.

| Part        | Holds, at position `size`                                                                                                                                                                                                                          | Order                                                                                                           |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `trust`     | The trust state: `approvers`, each with its keys; `threshold`; service `keys`, each with its `kinds`; `writer`; `webauthn`; the `pins` in force; the `modes` of contracts not `off`; and `registered`, SHA-256 of every public key ever registered | Approvers by `id`, keys by `keyId`, identifiers by `rpId`, pins by `name`, modes by contract, digests ascending |
| `approvals` | Per contract with an approval, the approvers who approved it                                                                                                                                                                                       | Contracts by digest, then approver `id`                                                                         |
| `requests`  | Per request with a decision: `last`, the entry digest of its last decision, and that decision's `contract`, `decision`, `basis` and `override` (an entry digest, or `null`)                                                                        | Requests by digest                                                                                              |
| `contents`  | The content digest of every entry after the basis entry                                                                                                                                                                                            | Ascending                                                                                                       |

With `last` and `basis`, these are exactly what RFC 0014's rules read of the entries before `size`. The `trust` part is the state the trust entries set, and `registered` keeps a public key from being registered twice. `approvals` is what a `mode.set` leaving `off` reads. `requests` is what `decision.recorded` (one decision per request, unless it supersedes the last) and `decision.override` (the decision's basis, not superseded, once) read. Digests are ordered by their `hex`, identifiers by code point.

**Why `contents` holds only entries after the basis.** `REPLAYED` refuses an entry whose content digest an earlier entry has. The content includes `basis`, and an entry is appended only while its basis is in force (`STALE`, which RFC 0014 checks first). So two entries with one content name one basis and both lie after it. The basis in force only moves forward, to a new entry. An entry naming the basis in force can therefore collide only with entries after the basis entry. The part grows with the record entries since the last trust entry, and starts again at each.

**A snapshot is a function of the history.** Replay is a function of the entries (RFC 0014, formal semantics 1), and each part's canonical form is a function of the state. So at each size there is exactly one correct `basis`, `last` and set of core parts, and two correct snapshots of one ledger at one size differ at most in `segments`, `previous`, `issuedAt` and which extensions they include. These are the snapshot's **determined members**: `ledger`, `size`, `root`, `last`, `basis`, `core`, and the digest of each extension part it includes. A snapshot is checked by comparing digests, never by interpreting a part.

**A part is content-addressed.** It names no ledger and no size, so an unchanged part keeps its digest from one snapshot to the next, and is stored once. The snapshot binds it to a ledger and a size.

**Extension state.** An extension (RFC 0014, section 5) whose rules read earlier entries, such as RFC 0018's gate, which refuses an override used twice, may define a **state part**: a format with its own identifier, a function of the entries before `size`, canonical in `verified-json-v1`, digested with SHA-256. The snapshot lists it under the extension's registered identifier. `ledger-1` never opens an extension part: a `ledger-1` verifier lists it `UNINTERPRETED`, as it lists extension entries. The extension's checker starts from it, compares it in an audit, and reports `SNAPSHOT_MISMATCH` in its own result. So a wrong extension part never changes a `ledger-1` result. An extension without a state part is checked only from the genesis, or its checks that read entries before the snapshot are not checkable, in the extension's own terms.

### 3. What a snapshot is trusted for

A verifier starting from a snapshot does not replay the entries before it. What it then relies on, and who could show it false:

| Member                              | From a snapshot, it rests on                                                                      | Checked by                                  |
| ----------------------------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `ledger`, `size`, `root`, `last`    | The checkpoint, under the writer's signature and the witnesses' cosignatures RFC 0014 already has | The verifier, against the checkpoint        |
| `basis`, the `trust` part           | The trust chain, which the verifier folds itself                                                  | The verifier                                |
| `approvals`, `requests`, `contents` | The writer's signature, and the cosignatures of any witnesses that replayed to `size`             | Anyone holding the entries before `size`    |
| Extension parts                     | The same                                                                                          | The extension's checker, with those entries |

**The trust state is checked, not trusted.** The verifier is given every trust entry before `size`, found by following `basis` back to the genesis, each with an inclusion proof under `root`. It folds them as RFC 0014's witness does before following a handover, and compares the result with the `trust` part. It checks `basis` against the entry at `size` − 1, given with its inclusion proof: if that entry is a trust entry, it is the basis; if a record entry, it names the basis in force when it was appended, which is still in force at `size`. It then knows the writer in force at `size` − 1, which is the only key a snapshot or its checkpoint verifies under. A snapshot never says who may sign it (RFC 0001, invariant 7). Two things rest on the history being append-valid and are checked only by replay: that no trust entry lies between two links of the chain, and the rule of a `mode.set` leaving `off`, which reads approvals.

**The record parts are the writer's word.** A verifier starting from a snapshot trusts that its record parts are what replay gives. Anyone holding the entries before `size` checks that by replaying them: a wrong part is `SNAPSHOT_MISMATCH`, which names it, and is proof against the writer, which signed it. A relying party that will not rest on the writer's word requires the cosignatures of witnesses that replayed (section 4), or audits.

**Accepting a snapshot.** A relying party accepts a snapshot as a starting point only if it passes the checks of the verification algorithm, is signed by the writer in force at `size` − 1 by the trust chain, and, where the relying party's policy says so, is cosigned over every core part by a quorum of its witnesses. Which witnesses, and how many, is the relying party's configuration, never the ledger's.

### 4. Witnesses and snapshots

A **replaying witness** cosigns snapshots. It is one of RFC 0014's witnesses that also replays record entries, which RFC 0014's open question 4 leaves open. A **snapshot cosignature** is its Ed25519 signature over `verified:ledger-snapshot-cosignature:v1\n` and the canonical `{ protocol, ledger, size, root, basis, core, extensions, cosignedAt }`, where `extensions` lists only the extension parts it computed.

A witness cosigns a snapshot only when:

- the writer it follows signed the snapshot, and it cosigned a checkpoint of that size and root;
- it replayed every entry from a snapshot it cosigned before, or from the genesis, to `size`, and computed every core part it signs and every extension part it lists, with those digests.

It stores, per ledger, the determined members of the last snapshot it cosigned. It never cosigns two snapshots of one size with different determined members. Given two writer-signed snapshots of one ledger, one size and one root that give one part two digests, it holds proof that the writer equivocated (`SNAPSHOT_EQUIVOCATION`). At most one of them is what replay gives.

A relying party whose policy needs replaying witnesses counts, per part, the witnesses whose cosignature covers it. A witness that does not implement an extension still cosigns the core.

### 5. Archiving and retention

**The archive list** at a snapshot is a part, with `protocol` `ledger-1` and `part` `segments`, listing the segments whose entries are 0 to `size` − 1, in order, contiguous, each once:

| Member   | Meaning                                         |
| -------- | ----------------------------------------------- |
| `start`  | Its first position                              |
| `size`   | One past its last position; a checkpoint's size |
| `root`   | The checkpoint root at `size`                   |
| `digest` | Its segment digest                              |
| `status` | `archived` or `deleted`                         |

Each snapshot's list extends the previous one's. A segment once listed keeps its range, root and digest in every later list: it is never re-cut or replaced, so its digest names it for good. Its status changes only from `archived` to `deleted`, and never back. A list that breaks this is `ARCHIVE_MISMATCH` against the previous snapshot.

**Moving entries out.** The writer keeps live the entries from its latest snapshot on. It MAY move any segment a snapshot lists, which lies wholly before that snapshot, to archive storage. It MUST keep each `archived` segment retrievable by its digest, as octets that are, or decode to, its canonical text, for the retention period the deployment declares. How the archive stores and serves octets is persistence, outside the protocol ([architecture](../governance/architecture.md)); what it returns is checked by its digest and its roots.

**The retention period** is the deployment's declaration. This RFC recommends making it in the ledger, by a `pin.set` of a `document` reference under the name `retention`, so that approvers set it at their threshold and every verifier sees it. `ledger-1` gives the pin no meaning beyond its being pinned.

**Deletion is never silent.** A segment leaves the archive only through a snapshot that lists it `deleted`, signed by the writer. Its range, root and digest stay listed. Its positions stay in the tree: anyone who kept a copy of one of its entries still proves it with an inclusion proof. Deleting removes octets. It changes no entry, root, checkpoint or state.

So every earlier position is, at any snapshot, in exactly one of three standings:

| Standing    | Meaning                                                                                           |
| ----------- | ------------------------------------------------------------------------------------------------- |
| `RETRIEVED` | Its segment was fetched, has its digest, and reproduces its roots                                 |
| `DELETED`   | A writer-signed snapshot lists its segment `deleted`. Its `issuedAt` is the writer's word on when |
| `LOST`      | Its segment is listed `archived` and the archive does not return it, or returns other octets      |

`LOST` is the writer's failure, never the ledger's invalidity. A writer that will not serve a segment and one that lost it look alike, and both are reported. A deletion before the declared period ends is shown by the snapshot that lists it, against the pin.

**Decisions that cite archived entries.** An entry in an archived segment stays recomputable: its decision is recomputed from its package (RFC 0014, section 9), and the entry, if needed, is fetched with its segment. A relying party learns a request's last decision at a snapshot from its `requests` row, without the segment. If the segment is deleted or lost, whatever needs that entry is `NOT_RECOMPUTABLE`, or the extension's `NOT_CHECKABLE`, as RFC 0014 and RFC 0018 treat any missing material: unchecked, never invalid.

### 6. Smaller without a change of trust

**Compression is an encoding, not content.** A segment or part MAY be stored and transported as one Zstandard frame ([RFC 8878](https://www.rfc-editor.org/rfc/rfc8878)) of its canonical text, with its content size declared and no dictionary, as `application/zstd`. Every digest is of the canonical text, never of the frame. So two encoders that compress differently produce frames that decode to the same octets, and compressing changes no digest, signature, root or trust. A verifier refuses a frame that declares no content size, or more than the limit, before decompressing it (`LIMIT`). A segment's names, members and repeated digests compress; its signatures and fresh digests do not.

**Large bodies are already references.** RFC 0014 bounds every entry (its open question 8 proposes 16 KiB of canonical entry), names every external object by digest, and keeps only a request's digest in the ledger (section 9). This RFC adds no rule there. A ledger that grows quickly does so by the number of entries, which snapshots and archiving address, not by their size.

**A snapshot is smaller than the history, not constant.** A `requests` row is under 500 octets of canonical text, one per request ever decided, against the entries appended for it. `contents` grows with the record entries since the last trust entry. Starting from a snapshot is linear in its parts, which are hashed, and in the entries after it, which are replayed. Open question 5 asks for parts a verifier reads row by row.

### 7. Verification modes

| Mode              | Given                                                                                                                                                                  | Establishes                                                                                                                                                                                                                        | Does not establish                                                                                                                               |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Full**          | RFC 0014's export from the genesis to the tip                                                                                                                          | All of RFC 0014's results. Each snapshot also given is compared with the replay                                                                                                                                                    | Nothing more than RFC 0014                                                                                                                       |
| **From snapshot** | A **compacted export**: a snapshot, its core parts, its checkpoint, its trust chain and last entry with inclusion proofs, and RFC 0014's export from `size` to the tip | The trust state at `size`; append validity from `size` on, given the record parts; that any earlier entry given with its inclusion proof is the entry at its position; who signed the snapshot, and which witnesses replayed to it | That entries before `size` were append-valid; that the record parts are what replay gives, beyond the writer's and the cosigning witnesses' word |
| **Audit**         | The segments of an archive list, fetched by digest, and the snapshots                                                                                                  | Every segment's integrity and roots; every snapshot's determined members against the replay; each earlier position's standing                                                                                                      | Anything about a `DELETED` or `LOST` range beyond its roots, its trust chain, and the snapshots that follow it                                   |

**Full** is RFC 0014's verification, unchanged. Its report is RFC 0014's.

**From snapshot** gives a report that states `from`, the snapshot's digest and size, and `appendValid` from that position. It also states `snapshot`: `SIGNED`, or `WITNESSED` when a quorum of the relying party's replaying witnesses cosigned every core part. A verifier MUST NOT report a ledger append-valid from the genesis when it started from a snapshot. A gate given a snapshot policy MUST NOT start from a snapshot that does not meet it. An earlier entry that a later entry, a recomputation or a relying party relies on is given with its inclusion proof under `root` or a later checkpoint's (`NOT_INCLUDED`): inclusion shows it is the entry at its position, and the snapshot that it was valid, on its signers' word.

**Audit** replays the segments of an archive list from the genesis, or from a snapshot already audited, and at each snapshot compares its determined members with the replay. Past a `DELETED` or `LOST` segment it can only start again from the next snapshot, on that snapshot's word, and it reports the audit `INCOMPLETE` with the ranges it could not replay. A snapshot after a lost range can never be audited: its record parts rest for good on the writer and the witnesses that replayed. Hence open question 2.

## The verification algorithm

**A snapshot**, given with an anchor (a trusted genesis digest, or a snapshot the relying party verified before), is checked in this order, stopping at the first failure:

| Step | Check                                                                                                                                                                                                             | Refusal                                         |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 1    | Within the limits                                                                                                                                                                                                 | `LIMIT`                                         |
| 2    | Canonical text; exactly the members of section 2, of their types; extensions ascending, each `id` once                                                                                                            | `MALFORMED`                                     |
| 3    | `protocol` is `ledger-1`                                                                                                                                                                                          | `UNSUPPORTED_PROTOCOL`                          |
| 4    | Every digest is SHA-256, 64 lowercase hex digits                                                                                                                                                                  | `MALFORMED_COMMITMENT`                          |
| 5    | `ledger` is the anchor's                                                                                                                                                                                          | `LEDGER_MISMATCH`                               |
| 6    | A checkpoint of `size` is given and verifies as RFC 0014, step 13, with this `root` and `last`                                                                                                                    | `ROOT_MISMATCH` and RFC 0014's checkpoint codes |
| 7    | The trust chain, from the anchor to `basis`: each trust entry has an inclusion proof under `root` and verifies as RFC 0014's steps against the fold before it, its position shown by the proof in place of step 6 | `NOT_INCLUDED` and RFC 0014's codes             |
| 8    | The entry at `size` − 1 has an inclusion proof under `root`, has the digest `last`, and gives `basis`                                                                                                             | `NOT_INCLUDED`, `SNAPSHOT_MISMATCH`             |
| 9    | The signature verifies under the writer in force at `size` − 1 by the fold                                                                                                                                        | `NOT_WRITER`, `SIGNATURE_INVALID`               |
| 10   | Each core part is given, has its digest, and is well formed and ordered                                                                                                                                           | `PART_MISSING`, `MALFORMED`                     |
| 11   | The `trust` part is the fold                                                                                                                                                                                      | `SNAPSHOT_MISMATCH`                             |
|      | **The snapshot is a starting point here.** Its record parts are the writer's word.                                                                                                                                |                                                 |
| 12   | Cosignatures, under the relying party's witness keys, per part                                                                                                                                                    | None: reported                                  |
| 13   | In full and audit: every determined member is what the replay gives                                                                                                                                               | `SNAPSHOT_MISMATCH`                             |
| 14   | Against any other writer-signed snapshot of the ledger at `size`: the same determined members where both have them; against the previous one, an archive list that extends it                                     | `SNAPSHOT_EQUIVOCATION`, `ARCHIVE_MISMATCH`     |

Step 7 checks every rule of a trust entry but one, a `mode.set` leaving `off`, which reads the approvals before it (section 3). Step 9 of RFC 0014 holds within a chain: two trust entries with one content would name one basis, and only one entry follows a link. From a snapshot anchor, the fold starts from that snapshot's `trust` part, the chain runs from its `basis`, and a consistency proof joins its checkpoint to this one (RFC 0014, step 14). Entries from `size` on are then verified as RFC 0014 says, from the state the parts give.

**A segment**, given with the roots that bound it, is checked in this order:

| Step | Check                                                                                      | Refusal                                                     |
| ---- | ------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| 1    | A frame declares its content size, within the limit; the segment is within the limits      | `LIMIT`                                                     |
| 2    | Canonical text, exactly the members of section 1; `protocol`; digests                      | `MALFORMED`, `UNSUPPORTED_PROTOCOL`, `MALFORMED_COMMITMENT` |
| 3    | It has the digest the archive list gives, and its `ledger`, `start` and `size`             | `SEGMENT_MISMATCH`                                          |
| 4    | The frontier gives the root at `start`, and is the frontier the previous segment ends with | `SEGMENT_MISMATCH`                                          |
| 5    | The frontier and its leaves give its `root`                                                | `ROOT_MISMATCH`                                             |
| 6    | Its entries, as RFC 0014's steps 1 to 12, in audit                                         | RFC 0014's codes                                            |

A segment that is not returned is not refused: its positions are `LOST`, reported.

## Outcomes that change

None. Every input RFC 0014 defines keeps its outcome: an export without a snapshot is verified as before, and its report is unchanged. The objects are new, and every check applies only to them, as RFC 0001, invariant 4 allows. If `ledger-1` is published before this RFC is accepted, this is a revision of it that only adds, recorded in its header; if after, it is part of it.

New refusal codes: `SNAPSHOT_MISMATCH`, `SNAPSHOT_EQUIVOCATION`, `PART_MISSING`, `NOT_INCLUDED`, `SEGMENT_MISMATCH`, `ARCHIVE_MISMATCH`. New standings and report members: `RETRIEVED`, `DELETED`, `LOST`; `SIGNED`, `WITNESSED`; an audit `COMPLETE` or `INCOMPLETE`; `from`. The others are RFC 0014's.

## Compatibility

- **Existing ledgers** need no migration. A snapshot is added beside a ledger and changes no entry, checkpoint or cosignature. A writer starts snapshotting at any checkpoint, and the first snapshot has `previous` `null`.
- **Verifiers** of RFC 0014 need no change: they verify from the genesis, as before. A verifier that implements this RFC claims it in its _Ledger verification_ profile (RFC 0004, rule 3), with the modes it supports.
- **Witnesses** need no change. One that replays may cosign snapshots; one that does not cosigns checkpoints as before.
- **Extensions** need no change. Without a state part, an extension is checked from the genesis only. RFC 0018 ([#60](https://github.com/dekrops/wvp/pull/60)) would gain a state part by a revision that only adds.
- **The registry of ledger extensions**, which RFC 0014 adds, would gain a column naming each extension's state format, or none (open question 3).
- **Relying parties** that do nothing keep verifying from the genesis. One that starts from snapshots configures its snapshot policy: whether replaying witnesses are required, which, and how many.

## Vectors

In `test-vectors/ledger/v1`, beside RFC 0014's, at least:

- **Valid:** a snapshot at size 1, of the genesis alone; after each core kind; with `contents` reset by a trust entry; verification from a snapshot agreeing with verification from the genesis, entry by entry; a snapshot anchored on an earlier snapshot; a snapshot at a handover checkpoint, signed by the outgoing writer, and the next by the incoming one; a chain of three segments from 0; a segment of one entry; a segment checked alone against two roots; a compressed segment, whose digest is its canonical text's; an extension part listed `UNINTERPRETED`; two snapshots at one size that differ only in `issuedAt`, `previous` and `segments`; a cosignature over the core without an extension part; a `DELETED` segment; a `LOST` one, and an audit `INCOMPLETE`.
- **Refused,** every new code, and: a snapshot omitting a `requests` row, which passes from the snapshot and then accepts a second decision for that request, and is `SNAPSHOT_MISMATCH` in audit; a snapshot omitting a content digest, which then accepts a replayed record entry, and is `REPLAYED` from the genesis; a `trust` part with an extra key; a `basis` older than the last entry's; a snapshot signed by the outgoing writer after a handover (`NOT_WRITER`); a snapshot signed in the checkpoint's domain; another ledger's snapshot; a `root` other than the checkpoint's; two snapshots at one size with two `requests` digests; a trust entry without its inclusion proof; a part out of order or with a duplicate; a segment with another digest, a frontier not the previous segment's, or leaves that do not give its root; an archive list with a gap, an overlap, a re-cut segment, or a `deleted` segment listed `archived` again; a frame that decompresses beyond the limit, or declares no size.
- **Witness:** a snapshot whose `approvals` differ from the witness's replay, which it does not cosign.
- **Merkle:** frontiers at sizes 1 to 8, 2^k and 2^k + 1, checked against an independent RFC 9162 implementation.
- **Order:** steps 9 and 11 failing at once, and 11 and 13.

All synthetic, with public test keys, as RFC 0014's.

## Security considerations

This RFC touches a signing input, digests and what they commit to, key validity and what a verified result may be relied on for (RFC 0001, section 9.1). **The adversary** may be the writer: it signs snapshots, chooses their parts, and runs the archive. It may hold some witnesses' keys, or a stolen writer key. **Assumed:** RFC 0014's assumptions; the relying party's anchor, witness keys and snapshot policy are what it intends.

**Prevented:**

- _A snapshot in the writer's name_ by anyone else, and _a snapshot under a key the snapshot names:_ the key is the one the trust chain gives at `size` − 1.
- _A wrong trust state:_ the verifier folds the trust chain itself (step 11).
- _Replaying a snapshot_ into another ledger, by `ledger`; at another position, by `size`, `root` and `last`; as another object, by its signing domain. A stale snapshot presented as the latest only makes the verifier replay more; how far its export reaches is RFC 0014's extent, against the relying party's latest checkpoint (`BEHIND`).
- _An outgoing writer's snapshot after a handover:_ `NOT_WRITER`.
- _Two states for one history, shown to different parties:_ two writer-signed snapshots with different determined members at one size prove equivocation, and a witness never cosigns both.
- _An altered or substituted segment:_ its digest, and its roots, which the checkpoints fix.
- _Silent deletion:_ a deletion is a signed listing; anything else is `LOST`, reported against the writer.
- _A decompression bomb:_ the limit applies before hashing.

**Not prevented:**

- _A snapshot that omits or changes a record item._ A missing `requests` row lets a second decision for that request pass from the snapshot; a missing content digest lets a record entry be appended twice; an extension part missing a used override lets it be used again. Each passes verification from the snapshot. Each is found by replay, by an audit while the segments exist, and is kept from a relying party that requires a quorum of replaying witnesses of which one is honest. Without such witnesses, before an audit, it is the writer's word. Once the segments are deleted or lost, nobody can find it.
- _A compromised writer key._ The thief signs snapshots consistent with real checkpoints and with false record parts, and shows them to relying parties without replaying witnesses. After a `writer.set`, its later snapshots are `NOT_WRITER`. Those it signed before stay validly signed: a relying party that learns of a compromise starts again from the last snapshot that replaying witnesses cosigned before it, or audits. A new writer after a handover holds no state it did not compute: its first snapshot SHOULD follow its own replay from the genesis, or from a snapshot replaying witnesses cosigned.
- _An unavailable archive._ Verification from a snapshot needs no archive. Audit and citations of archived entries do. A writer can prevent an audit by not serving segments. That is reported `LOST`, and no relying party can then check the snapshots after them. A tenant that keeps its own copy, or replays as a witness, is not exposed to this.
- _A lying writer before a snapshot is cosigned,_ as RFC 0014's window before a checkpoint is.

**Privacy.** A snapshot discloses state in one object: approver identifiers, service keys, pins, modes, and every request's digest with its last decision and override. That is no more than the entries disclose to whoever holds the export, but it is compact, and it outlives the deletion of the segments it was computed from: deleting a range does not erase what the snapshots after it derived. A replaying witness sees every entry. Selective disclosure, showing one row without the others, is out of scope (open question 5).

**Primitives.** SHA-256 (FIPS 180-4); Ed25519 (RFC 8032, under RFC 0002, rule 1); RFC 9162's tree. Zstandard (RFC 8878) is an encoding, decoded before anything is hashed or verified, and no property here rests on it. None is new.

**Review.** No person other than the author has reviewed this RFC. Under RFC 0001, section 9.1, it cannot become Final until a competent reviewer has, and is named here.

## Formal semantics

Nothing is proved with this RFC. Worth proving in Lean, over RFC 0014's model with signatures assumed and digests injective:

1. **Soundness of starting from a snapshot.** If a snapshot's determined members are what replay gives at _n_, verifying entries _n_ to _m_ from it gives the same results, and the same state at _m_, as verifying 0 to _m_ from the genesis.
2. The parts at _n_ are a function of entries 0 to _n_ − 1, and so are their digests.
3. **The window.** In an append-valid history, an entry that passes `STALE` at _p_ has a content digest equal to an earlier entry's only if that entry lies after the basis in force at _p_.
4. The `trust` part at _n_ is the fold of the trust chain to the basis at _n_ (RFC 0014, formal semantics 5), and that basis is given by the entry at _n_ − 1.
5. Folding a frontier with leaves gives RFC 9162's root, and the frontier at the end of a segment is the frontier at the start of the next.
6. Removing every extension part changes no `ledger-1` result.

**Tested only:** encodings, ordering, compression, limits. **Neither:** the archive's availability, retention, and time.

## Alternatives

- **Checkpoints only.** They show that a history is whole and unrewritten, not what state it gives. Replay stays linear.
- **Pruning without snapshots.** Dropping old entries and keeping checkpoints leaves a verifier unable to compute the state that later entries are checked against. Either verification stops, or the verifier takes the state from the operator unsigned, which nobody can check afterwards.
- **A snapshot as an entry.** The writer signs no entry (RFC 0014, section 6), and a new core kind would change the outcome of inputs that are `UNKNOWN_KIND` today, which is a new version. Beside the ledger, a snapshot changes nothing in it.
- **Snapshots signed by approvers.** People cannot check a state without replaying it, so their signatures would add authority without adding a check. The writer is the party accountable for the history, and its signature is what makes a wrong snapshot proof against it.
- **The trust chain alone.** RFC 0014's open question 2 notes it leaves record rules unchecked. The record parts close that, on the writer's word, checkable by replay.
- **A ledger per tenant per year.** A new genesis each year resets length without snapshots. It breaks continuity of trust: relying parties need a new anchor out of band each year, approvers sign a new genesis, the trust chain no longer reaches the original, witnesses start over, and a request decided in December and acted on in January spans two ledgers.
- **Recursive succinct proofs.** A proof that the previous state followed from the genesis, and a proof that the new entries are valid from it, can be composed into one proof that the new state follows from the genesis: incrementally verifiable computation, or proof-carrying data. An earlier internal direction had this shape: a proof of the previous statement and a proof of the new work give a proof of the new statement. Such a proof would remove the trust in the writer's record parts, and the replaying witnesses' role. It is future work: proving Ed25519, WebAuthn signatures and SHA-256 inside such a system is costly, and RFC 0001, section 9.1 requires primitives named by a published standard, which these proof systems do not yet have. A snapshot would carry such a proof beside its signature in a later version; nothing here prevents it.

## Open questions

1. **Snapshot frequency.** By entries or by time. Proposed: a snapshot at the end of every segment, and a segment at most 2^20 entries or one day, whichever comes first.
2. **Witnesses before archiving.** Whether a writer MUST hold a quorum of replaying witnesses' cosignatures on a snapshot before it archives the segments under it, so that no snapshot is past audit before someone other than the writer replayed it. Proposed: SHOULD, and MUST before deleting.
3. **The extension state format registry.** Whether the registry of ledger extensions gains a column for the state format, and whether formats are registered there or only named by the extension's specification.
4. **Retention defaults.** Whether `ledger-1` defines a default period, or only the `retention` pin, and whether names like `retention` are reserved (RFC 0018, open question 1, asks the same of pin names).
5. **Parts read row by row.** An authenticated map, a sorted Merkle tree per part, would let a verifier hold only the rows it reads, with proofs of absence, so that starting from a snapshot is logarithmic and a single row is disclosed alone.
6. **A bounded request index.** `requests` grows with every request ever decided, because a request may be decided again at any time. A rule in `ledger-1` bounding when a request's decision may be superseded would let rows leave the index. That is a change to RFC 0014, and a question for it.
7. **Who authorizes deletion.** The writer alone, as proposed, or a threshold of approvers, by a pin naming what may be deleted.
8. **Limits.** Proposed: 2^20 entries and 1 GiB of canonical text per segment; 1 GiB per part; 64 extension parts per snapshot.

## Decision

Not made. The review period of RFC 0001, section 5, has not started. This RFC will be accepted on the maintainers' judgement alone only if it says that it had no outside review (section 7.4).

## Implementation

Not implemented.

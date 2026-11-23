# RFC 0014: Ledger v1

|            |                                            |
| ---------- | ------------------------------------------ |
| RFC        | 0014                                       |
| Status     | Draft                                      |
| Author     | Zin Nam                                    |
| Created    | 2026-11-20                                 |
| Affects    | New: `ledger-1`. Nothing existing changes. |
| Supersedes | Nothing                                    |

A new specification, `ledger-1`: a signed, append-only log of who may sign what and of the decisions made under it, with Merkle checkpoints that parties other than its operator witness, and an export that anyone verifies offline. It names contracts, packages, records and system models by digest and defines none of them. This RFC proposes the design for review. It does not publish `ledger-1`.

## Motivation

The family verifies objects, but a relying party usually acts on a state: which contracts are in force, in which mode, who may approve, which decision answered which request. That state lives in an operator's ledger, and nothing here says what an entry is or how an outsider checks one. [The architecture map](../governance/architecture.md) puts ledgers outside the protocol as persistence: right for where entries are stored, wrong for what they say.

| #   | Need                                       | Missing today                                                                     |
| --- | ------------------------------------------ | --------------------------------------------------------------------------------- |
| L1  | An operator hosts ledgers for many tenants | Entries the operator cannot write in a tenant's name; a history it cannot rewrite |
| L2  | A tenant witnesses its hosted ledger       | A checkpoint it can check and cosign, and proof that a later one extends it       |
| L3  | A tenant moves to self-hosting             | An export that verifies offline, and a handover the old operator cannot undo      |
| L4  | Gates act on many decisions per second     | Small entries, signatures that do not wait on the head, proofs that stay small    |

Merge gating is the first use of several. Nothing in the ledger belongs to one system of record.

**Prior art.** Counterplay's ledger, the reference, has author-signed entries, a trust state replayed from a genesis, and signatures bound to a trust state instead of a position. It is not public and is not a WVP specification. This RFC restates that design in this family's encodings and adds checkpoints, witnesses, export and extension kinds, answering [open question B2](../governance/open-questions.md) for ledgers. Its kinds differ where hosting needs it, and a decision recorded in error is superseded, not withdrawn.

## What changes

A new specification, `ledger-1`, in the family's encodings with [RFC 0002](0002-inputs-every-verifier-refuses-alike.md) applied from the start: `verified-json-v1`, digests as `{ "algorithm": "sha-256", "hex" }` everywhere, as in [RFC 0015](https://github.com/dekrops/wvp/pull/58), Ed25519 signatures as `{ "scheme", "keyId", "encoded" }`, keys as a trust registry spells them (with `rpId` and `credentialId` for a passkey), canonical instants.

_Authors_ sign entries: _approvers_ are people, with passkeys or Ed25519 keys; _services_, such as deciders, hold Ed25519 keys. The _writer_ is the one operator that appends and signs checkpoints. _Witnesses_ cosign checkpoints.

### 1. Identity and genesis

A ledger is named by the **entry digest of its genesis**, which the relying party obtains out of band: which ledger to trust is never read from a ledger (RFC 0001, invariant 7). Every later entry names it, so ledgers never mix.

The genesis is the entry at sequence 0, of kind `genesis`. Its body names `name` (for people), a random `nonce` of at least 16 octets, the `approvers` (each `{ id, keys }`, one to eight keys), the `threshold` of distinct approvers a trust entry needs, the `writer`'s Ed25519 key, `webauthn` (each relying party identifier passkeys are checked against, with the origins assertions may come from), and initial service `keys`. Every approver it names signs it. It is the **first trust basis**.

### 2. Entries

A signed entry is `{ "entry": { … }, "signatures": [ … ] }`. The entry has exactly `protocol` (`ledger-1`), `ledger` (the genesis digest), `sequence`, `previous` (the entry digest before it), `basis` (section 3), `kind`, `at` (the time its authors assert, which no rule reads) and `body`, and optionally `nonce`, the base64 of 16 random octets. `ledger`, `previous` and `basis` are `null` exactly in the genesis.

- The **entry digest** is SHA-256 of the canonical entry. It names the entry in the next `previous`, in a `basis`, in a Merkle leaf and in other bodies.
- The **content** is the entry without `sequence` and `previous`. Its SHA-256 is the **content digest**.
- Every signature is over `verified:ledger-entry:v1\n` followed by the canonical content, a signing domain of its own.

**Authors do not sign the position.** The writer fills in `sequence` and `previous`, so authors sign without knowing the head, many at once. Two rules close replay instead: the basis must be in force (section 3), and **no two entries of a ledger have one content digest** (`REPLAYED`). An author who means to record the same content twice adds a `nonce` rather than relying on `at`. Signatures are in neither digest, so gathering a threshold renames nothing; a checkpoint fixes who signed (section 7).

`Ed25519` signatures are verified as RFC 0002, rule 1 defines. A `webauthn` signature carries `credentialId`, `authenticatorData`, `clientDataJSON` and `signature`; its challenge is SHA-256 of the signing input; it is checked as steps 5 to 15 of [contract approval v1](../protocols/contract-approval/v1/SPEC.md), section 6, against the key's `rpId` and the origins listed for it at that position; and its user-verified flag must be set, since an entry can change what is enforced. Any signature that fails refuses the entry; none is set aside, since every key here is the ledger's own.

### 3. The trust basis

The **state** at a position is the fold of the entries before it: approvers and keys, threshold, service keys and the kinds each may sign, writer, WebAuthn identifiers and origins, pins, each contract's mode and approvals, decisions and overrides.

A **trust** kind changes who may sign what, or what is enforced. A **record** kind changes neither. The **trust basis** at a position is the entry digest of the latest trust entry before it.

- Every entry names the basis it was signed against and is appended only while that basis is in force (`STALE`). Only trust entries change approvers, keys and threshold, so its signers are checked against the state they saw.
- A trust entry's `basis` is the trust entry before it: the trust entries form a chain of their own.
- A record entry lands anywhere before the next trust entry, so a busy ledger never blocks an approval. A trust entry voids what was signed against the basis it replaces: **a decision is recorded only under the trust state in force when it is appended.**

A contract approval is a record entry. Approvals are only added, and the one rule that reads them is checked at the mode change. If they moved the basis, one approver could void the others' pending trust entries by approving contract after contract.

**Authorization is by position.** A key removed at _k_ signs nothing appended after _k_, whatever `at` says.

### 4. Core kinds

The set is closed: a kind without `/` that is not listed is `UNKNOWN_KIND`. "Threshold" is distinct current approvers, at least the threshold in force; two keys of one approver count once. Besides the genesis:

| Kind                                      | Class  | Body                                                                                            | Signed by     | Rule                                                                               |
| ----------------------------------------- | ------ | ----------------------------------------------------------------------------------------------- | ------------- | ---------------------------------------------------------------------------------- |
| `approver.add`, `approver.remove`         | trust  | `approver`                                                                                      | Threshold     | A new approver does not count toward its own entry; `threshold` approvers remain   |
| `approver.key.add`, `approver.key.remove` | trust  | `approver`, a key or `keyId`                                                                    | Threshold     | One to eight keys                                                                  |
| `threshold.set`                           | trust  | `from`, `to`                                                                                    | Threshold     | `from` is in force; `to` is 1 to the number of approvers                           |
| `key.add`, `key.remove`                   | trust  | A service key, or `keyId`                                                                       | Threshold     |                                                                                    |
| `writer.set`                              | trust  | `writer`                                                                                        | Threshold     | Section 8                                                                          |
| `webauthn.set`                            | trust  | As the genesis                                                                                  | Threshold     | Every registered passkey's `rpId` stays listed                                     |
| `pin.set`                                 | trust  | `name`, a reference or `null`                                                                   | Threshold     | Pins external material (section 9)                                                 |
| `mode.set`                                | trust  | `contract`, `from`, `to`: `off`, `shadow`, `enforcing`                                          | Threshold     | `from` is in force; leaving `off` needs approvals by `threshold` current approvers |
| `contract.approve`                        | record | `contract`, `shown` (digest of what was shown), `approver`                                      | That approver | Once per approver and contract                                                     |
| `decision.recorded`                       | record | `request`, `contract`, `package`, `decision`, `evaluator`, optional `explanation`, `supersedes` | A service key | Mode not `off`; one decision per request, unless it supersedes the request's last  |
| `decision.override`                       | record | `decision` (entry digest), `reason` (≤ 512 octets)                                              | Threshold     | `UNDETERMINED`, `enforcing`, the decision's `basis`, not superseded, once          |

A public key is registered at most once, ever. A **service key** registration is a trust-registry entry (RFC 0002, rule 5) plus `kinds`, the entry kinds it may sign; for entries it is valid from its `key.add` to its `key.remove`, and its times are not read. A state's service keys, without `kinds`, form a trust registry that a relying party may choose to use.

An override leaves the decision `UNDETERMINED`: it records that a threshold of approvers let one request proceed, and why. Sharing the decision's basis, it lapses with any trust change. `CONTRADICTED` cannot be overridden; that is a change of contract or mode.

**A decision is not final; a request is.** Under Language 1, an `UNDETERMINED` answer can become `SUPPORTED` when missing evidence arrives. A request names its cutoff and evidence (section 9), so a re-ask is a new request with its own decision, and a gate reads the latest request for a subject. `supersedes`, the entry digest of the request's last decision, marks that decision recorded in error, in place of a general withdrawal; the superseded decision's override lapses, and none can follow. No core kind withdraws any other entry (open question 6).

### 5. Extension kinds

Another specification may define kinds named `<identifier>/<name>`. The identifier is assigned in [the registry of ledger extensions](../governance/ledger-extensions.md), by the RFC defining the specification or by a pull request to the registry, so no two specifications claim one. An extension kind is always a **record** kind, never moving the basis or changing the core state. It is authorized by a service key whose `kinds` include it, which approvers register at the threshold. Its body is bounded and otherwise not read.

A verifier runs every step on an extension entry except the kind's own rules, and lists it `UNINTERPRETED`, which is not a refusal. The defining specification reports its own result beside the ledger's and never changes it. So one input has one `ledger-1` result, whatever extensions a verifier knows. A gate must not act on an entry that is `UNINTERPRETED`: only its signers and shape were checked.

The ledger shows what was decided, not what a gate did. A gate-decision extension, RFC 0016, written next to this one, records whether a gate acted on a decision; only such a record shows that a `decision.override` let a request proceed.

### 6. One writer

One writer at a time, the key the state names, assigns positions and signs checkpoints. A ledger is a sequence, never a graph. Within one basis the writer chooses where record entries go, which is no more than delaying them. It signs no entry, so two differing copies prove nothing against it; two inconsistent checkpoints it signed prove it equivocated. A verifier never merges continuations: it reports `EQUIVOCATION` and picks neither.

### 7. Checkpoints and witnesses

Entries are the leaves of the Merkle tree of [RFC 9162](https://www.rfc-editor.org/rfc/rfc9162), section 2.1, with SHA-256. Leaf _i_ is the canonical `{ "entry", "signers" }`: entry _i_'s entry digest, and the `keyId`s of its signatures in ascending order. Inclusion and consistency proofs are those of its sections 2.1.3 and 2.1.4.

**A checkpoint fixes who signed.** Otherwise the writer could serve, under one cosigned root, a copy of an entry with a signature removed, and give chosen relying parties `UNAUTHORIZED` for a valid history, which no witness could tell. Signature bytes are not fixed, so an ECDSA signature rewritten to its other valid form changes no leaf.

A **checkpoint** is [claim registration v1](../protocols/claim-registration/v1/SPEC.md)'s head (section 3.11), with the genesis digest for the registry's name and the root added:

```json
{
  "checkpoint": {
    "protocol": "ledger-1",
    "ledger": { "algorithm": "sha-256", "hex": "…" },
    "size": 1048576,
    "root": { "algorithm": "sha-256", "hex": "…" },
    "last": { "algorithm": "sha-256", "hex": "…" },
    "issuedAt": "2026-11-20T10:00:00Z"
  },
  "signature": { "scheme": "Ed25519", "keyId": "…", "encoded": "…" }
}
```

It is signed over `verified:ledger-checkpoint:v1\n` and the canonical `checkpoint` by the writer in force at entry `size − 1`.

A **cosignature** is a witness's Ed25519 signature over `verified:ledger-cosignature:v1\n` and `{ protocol, ledger, size, root, cosignedAt }`. A witness cosigns only a checkpoint signed by the writer it follows that, against the last one it cosigned, is no smaller, has a consistency proof that verifies, and at equal size has the same root. It **stores** only that checkpoint and the writer key, per ledger.

**Before following a handover,** a witness checks the `writer.set`'s inclusion proof and its signers against the trust state, the fold of the trust chain alone (`basis` back to the genesis), not of every entry. A witness may also require the tenant's cosignature on the handover checkpoint first.

A witness lets a relying party show:

- **truncation:** an export that ends before a cosigned size (`BEHIND`), or a smaller checkpoint issued later (`WITHHELD`);
- **a fork:** two writer-signed checkpoints of equal size with different roots, or with no consistency proof between them. Relying parties that share one honest witness never accept two histories;
- **a withheld entry:** an author's inclusion proof under an earlier checkpoint, which a later one either keeps or contradicts.

Which witnesses count, keys and quorum, is the relying party's configuration, never read from a ledger. The case built for is a tenant witnessing its hosted ledger: the operator cannot rewrite that history, or show the tenant's auditor another, without the tenant's witness refusing.

### 8. Export and handover

An **export** is one ledger's signed entries from 0 to _n_, with checkpoints, cosignatures and consistency proofs between successive checkpoints. References stay digests. It verifies offline from a **trusted genesis digest**, or from a **trusted checkpoint** whose size the export reaches and whose root it has there.

**Handover**, to self-hosting for instance, is a `writer.set` the outgoing writer appends at _k_, with a last checkpoint of size _k_ + 1, which witnesses check before following (section 7). After it only the new writer's checkpoints verify; identity, trust state and history are unchanged, and whatever the old operator appends after _k_ sits under checkpoints it cannot sign. A passkey works for its `rpId` only, so passkeys move first: a `webauthn.set` listing the new domain, then new approver keys.

**Many tenants** are many ledgers, one genesis each, possibly under one writer key. A checkpoint names its ledger, so its signature fits no other.

### 9. References by digest

External objects are named by **references**, in the shape of [work relation v1](../protocols/work-relation/v1/SPEC.md), section 2: `{ kind, digest }`, with an optional `id` that finds the object and never names it.

| Kind           | Object                                                               | Digest                        |
| -------------- | -------------------------------------------------------------------- | ----------------------------- |
| `contract`     | A Work Contract Language contract                                    | As the language defines it    |
| `package`      | A WVP package                                                        | Its package commitment        |
| `record`       | An evidence statement                                                | Its statement digest          |
| `request`      | What a decision answers (below)                                      | SHA-256 of its canonical form |
| `system-model` | A system model, in RFC 0015's `system-model-1` format. `id` required | Its model digest              |
| `document`     | Anything else                                                        | SHA-256 of its octets         |

Other specifications add kinds as they add entry kinds.

**The request** is an object with exactly `subject`, what is decided as the system of record names it (a repository and a pull request, say), at most 256 octets; `cutoff`, the instant evidence was gathered up to; `evidence`, SHA-256 of the canonical array of the statement digests asked about, ascending; and `nonce`, the base64 of 16 random octets, as RFC 0015 gives parts. Its digest is SHA-256 of its canonical text, so "one decision per request" holds across producers. It is kept with the package, never in the ledger, and its nonce keeps its digest from confirming a guess.

**Replay never opens a reference.** Append validity is a function of the entries alone: a ledger verifies with every package, record and model deleted, and nothing kept beside it makes it valid or invalid. `ledger-1` defines no kind or member of any system; the model format is `system-model-1`, and a model's content may be licensed separately.

**Recomputation** is a second level, reported apart: each decision whose package is given is verified under the package's own specification and the relying party's registry, and `AGREES`, `DISAGREES` or is `NOT_RECOMPUTABLE`. A missing package never makes a ledger invalid.

### 10. Throughput

- **Small entries.** A synthetic `decision.recorded` is 887 octets of canonical text, 1,054 signed. Limits bound every append and replay step.
- **Batching.** The writer appends many entries per durable write and signs one checkpoint per batch. An author gets its sequence at once and a logarithmic inclusion proof at the next checkpoint; a witness checks one consistency proof per checkpoint.
- **Parallel verification.** Only the fold is sequential. Each Ed25519 signature is checked alone: batch verification uses the cofactored equation, which RFC 0002, rule 1 does not.
- **One writer bounds a ledger's rate.** More rate means more ledgers (open question 7).

## The verification algorithm

Each entry is checked against the state after those before it. Checks run in this order and stop at the first failure, reported with the sequence.

| Step | Check                                                                                                                                                             | Refusal                                                                            |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| 1    | Within the limits                                                                                                                                                 | `LIMIT`                                                                            |
| 2    | Canonical text; exactly the members of section 2 and of a core kind's body, of their types; no `keyId` signs twice                                                | `MALFORMED`                                                                        |
| 3    | `protocol` is `ledger-1`                                                                                                                                          | `UNSUPPORTED_PROTOCOL`                                                             |
| 4    | Every digest is SHA-256, 64 lowercase hex digits                                                                                                                  | `MALFORMED_COMMITMENT`                                                             |
| 5    | At 0, a genesis whose digest is the trusted genesis digest, or a checkpoint anchor's `ledger`; after 0, `ledger` is that digest                                   | `GENESIS_INVALID`, `LEDGER_MISMATCH`                                               |
| 6    | `sequence` is the position; `previous` is the entry digest before it                                                                                              | `GAP`, `PREVIOUS_MISMATCH`                                                         |
| 7    | A core kind, or an extension name                                                                                                                                 | `UNKNOWN_KIND`                                                                     |
| 8    | `basis` is the basis in force                                                                                                                                     | `STALE`                                                                            |
| 9    | No earlier entry has this content digest                                                                                                                          | `REPLAYED`                                                                         |
| 10   | Every signature is by a key the state holds, and verifies                                                                                                         | `UNKNOWN_KEY`, `SIGNATURE_INVALID`                                                 |
| 11   | The signers are those the kind requires                                                                                                                           | `UNAUTHORIZED`                                                                     |
| 12   | A core kind's rules hold. An extension entry is listed `UNINTERPRETED`                                                                                            | `STATE`                                                                            |
|      | **Append validity is established up to this entry.**                                                                                                              |                                                                                    |
| 13   | Each checkpoint is well formed, names this ledger, is the writer's in force at `size − 1`, and has the export's `root` and `last` where the export reaches `size` | `MALFORMED`, `LEDGER_MISMATCH`, `NOT_WRITER`, `SIGNATURE_INVALID`, `ROOT_MISMATCH` |
| 14   | Checkpoints in pairs, as claim registration compares heads; consistency proofs verify                                                                             | `EQUIVOCATION`, `WITHHELD`, `INCONSISTENT`                                         |
| 15   | A checkpoint anchor: the export reaches its size and has its root                                                                                                 | `BEHIND`, `ANCHOR_MISMATCH`                                                        |
| 16   | Cosignatures, under the relying party's witness keys                                                                                                              | None: reported                                                                     |

Step 8 precedes step 10, so a signature by a key removed since is `STALE`, which says what happened. A `webauthn` signature that fails a step of contract approval v1, or lacks user verification, is `SIGNATURE_INVALID`.

A report states apart, never as one "valid": `appendValid`; `checkpointed`; `witnessed`, which policy witnesses cosigned and when; `extent`, `CURRENT`, `BEHIND` or `AHEAD` against the relying party's latest checkpoint, as claim registration defines them; `uninterpreted`; and `standing`, `WITNESSED` when append-valid with the policy's quorum, else `UNWITNESSED`. A gate given a witness policy MUST fail on `UNWITNESSED`, and no verifier may call an unwitnessed ledger complete.

## Claim registration's log, and why this is not it

`ledger-1` takes from claim registration v1 its encoding, digest and signature shapes, a signing domain per object, the chain (`sequence`, `previous`), the head (`size`, `last`, `issuedAt`), and the head comparisons that rest on what the writer signed: where an export ends against a checkpoint (`BEHIND`, `CURRENT`, `AHEAD`), and two heads (`CONSISTENT`, `WITHHELD`, `EQUIVOCATION`). Not an entry against a head: its `WITHHELD` and `PREDATED` rest on a `receivedAt` the registry authenticates, and no ledger entry has an authenticated time, so inclusion proofs show a withheld entry instead (section 7). It differs where the job differs:

| Claim registration v1                      | `ledger-1`                                    | Why                                                                                             |
| ------------------------------------------ | --------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| The registry signs every entry             | Authors sign entries; the writer, checkpoints | A registry is trusted for when it received claims; an operator must write in no one's name (L1) |
| No trust state                             | A trust state replayed from the genesis       | Who may sign what is the ledger's content                                                       |
| Named by the registry's name               | By its genesis digest                         | Tenants under one operator must never mix                                                       |
| Inclusion by segment; no witnesses         | Merkle proofs; cosignatures                   | A segment grows with the log; L2                                                                |
| `receivedAt` authenticated by the registry | No entry time authenticated                   | No party in a ledger is trusted for time                                                        |

Reusing that log as it is would put the operator's signature on every entry, and changing it is a new version anyway (invariant 2). The other direction works: a registry could keep its log as a `ledger-1` ledger, its own records as extension kinds, in a claim registration v2 (open question 9).

## Outcomes that change

None. `ledger-1` is a new identifier in a new directory with its own vectors (invariant 2). It reads no existing object except to compare digests, and no published vector changes.

New refusal codes: `LIMIT`, `LEDGER_MISMATCH`, `UNKNOWN_KIND`, `STALE`, `REPLAYED`, `UNAUTHORIZED`, `STATE`, `NOT_WRITER`, `ROOT_MISMATCH`, `INCONSISTENT`, `ANCHOR_MISMATCH`. The others are claim registration v1's codes and outcomes.

## Compatibility

- **Existing specifications** do not change. A `contract.approve` entry and a contract approval v1 object have different signing inputs; neither verifies as the other. A reference kind for ledger entries in work relation would be a revision that only adds (invariant 4).
- **Producers.** A ledger in another format, the reference's included, cannot be converted: its authors signed other bytes. `ledger-1` starts from a new genesis.
- **Verifiers** are new, with a profile under RFC 0004, rule 3: _Ledger verification_, the canonical encoding and the `ledger-1` parts.
- **Relying parties** configure an anchor and, for `WITNESSED`, witness keys and a quorum.
- **The architecture map** keeps storage outside the protocol and brings entries, checkpoints and exports inside.

## Vectors

In `test-vectors/ledger/v1`, at least:

- **Valid:** each core kind; a record entry landing after others signed since its basis; approvals in both orders, then a mode leaving `off`; a threshold met by an Ed25519 key and a passkey; an override; a re-asked request; a superseded decision; contents equal but for `nonce`; an extension entry; every referenced object absent; a handover; `WITNESSED` and `UNWITNESSED`.
- **Refused,** every code, and: an entry appended twice; an approval by a key removed since (`STALE`); one approver's two keys toward a threshold of two; a removed key registered again; content signed under another domain; a passkey without user verification, from an unlisted origin, or for another `rpId`; a second decision for a request without `supersedes`; an override of `CONTRADICTED`, of a superseded decision, across a trust change, or of an `UNDETERMINED` decision recorded under `shadow`; an extension entry by a key not registered for it; an entry served with a signature removed under its checkpoint's root; the outgoing writer's checkpoint after a handover; two checkpoints of one size with different roots; an export shorter than its anchor.
- **Witness:** a `writer.set` signed by the writer alone, which a witness does not follow.
- **Merkle:** sizes 1 to 8 and 2^k + 1, checked against an independent RFC 9162 implementation.
- **Order:** steps 8 and 10 failing at once, and 9 and 11.

All synthetic, with public test keys and a software authenticator. ECDSA signatures are randomized, so those vectors are never regenerated.

## Security considerations

This RFC touches signing inputs, digests, key validity, time and authority (RFC 0001, section 9.1). **The adversary** may be the writer: it controls storage, order, what it serves to whom and every time it asserts, and may hold some authors' and witnesses' keys. **Assumed:** the signature schemes and SHA-256 hold; the relying party's anchor and witness keys are what it intends; an authenticator keeps its key.

**Prevented:**

- _An entry in an author's name._ Being the writer authorizes nothing.
- _Replay:_ of a trust entry, by the basis; of any entry, by its content; into another ledger, by the genesis; as another object, by the signing domain.
- _Backdating a key._ A removed key signs nothing appended later, whatever it dates. This answers open question A2 for ledgers, by position.
- _A rewritten, reordered or truncated history,_ once a checkpoint over it is cosigned by a witness the relying party requires; _a fork_ shown to relying parties that share an honest witness.
- _A decision under a trust state it did not see,_ and _an extension changing trust._
- _A valid history failing for chosen parties,_ served with a signature removed: a leaf fixes who signed.
- _Moving the witnesses with a stolen writer key,_ by a `writer.set` to the thief's key that they would follow, refusing the real operator's checkpoints, before replay found it invalid: a witness checks its signers first.

**Not prevented:**

- _A lying writer before witnessing._ Until a checkpoint is cosigned, or with no witnesses, it can fork, drop the tail or show two histories. The window is the checkpoint interval plus the witnesses' delay.
- _Withholding._ The writer can decline or delay an entry, or serve fewer entries than a checkpoint covers; only the last is detected. A signed entry shows it was signed, not submitted.
- _Key compromise._ A threshold of approvers' keys changes anything. A stolen writer key writes no entry and moves no witness, and inconsistent checkpoints it signs prove the lie; with enough witness keys as well, it can fork one relying party's view. User verification does not stop a coerced approver.
- _Time._ `at`, `issuedAt` and `cosignedAt` are their signers' word. A signature stays usable while its basis holds (open question 5).
- _A wrong decision._ Nothing here says a source told the truth, and `shown` is the producer's word.
- _An invalid record entry under a cosigned checkpoint._ A witness replays the trust chain at most, so it vouches for one history, not for its validity; replaying finds the entry.

**What a verifier needs from a referenced system model.** To check entries, nothing. To recompute a decision that uses a model's rules, exactly those parts, at exactly the referenced digest. `system-model-1` commits to each part, so those parts travel with the package and nobody is trusted for content (open question 1).

**Privacy and tenancy.** A digest of a guessable value discloses it, so such a value is salted wherever it is digested, the ledger included: a request, a model part and the genesis carry a nonce, and a subject never enters the ledger. Names, reasons, keys and times are in clear to anyone given the export. Deleting material leaves the ledger valid and its decisions `NOT_RECOMPUTABLE`. A witness learns size, root and rate, and at a handover the trust chain. Tenants are separated by genesis.

**Primitives.** Ed25519 (RFC 8032, under RFC 0002, rule 1); ECDSA P-256 (FIPS 186-5) and RSASSA-PKCS1-v1_5 (RFC 8017) within Web Authentication Level 2; SHA-256 (FIPS 180-4); RFC 9162's tree and proofs. None is new.

**Review.** No person other than the author has reviewed this RFC. Under RFC 0001, section 9.1, it cannot become Final until a competent reviewer has, and is named here.

## Formal semantics

Nothing is proved with this RFC, and nothing rests on the reference's own model, which is not public. Worth proving in Lean, over a model of steps 1 to 14 with signatures assumed and digests injective:

1. Replay is a function of the entries and the anchor.
2. Each entry's signers meet its kind's requirement in its basis's state, which equals its position's state in approvers, keys, threshold, writer, pins and modes.
3. Contents are unique, and each entry lies between its basis and the next trust entry.
4. Replacing every extension body changes no state, basis or result.
5. Following `basis` back visits every trust entry, and folding those alone gives the trust state.
6. Every override names an `UNDETERMINED`, unsuperseded decision under an enforcing contract, with the same basis.
7. If a consistency proof from (_n_, _r_) to (_m_, _r′_) verifies, the first _n_ leaves under _r′_ are those under _r_.
8. After a `writer.set` at _k_, no checkpoint above size _k_ + 1 verifies under the outgoing key.

**Tested only:** encodings, signatures, assertions, limits. **Neither:** witness independence, and time.

## Alternatives

- **A blockchain** orders entries from writers that trust no one. A ledger has one writer and needs one unrewritten history that everyone sees; witnesses give that without fees, delay to finality, a token, or a permanent public copy of what a tenant may have to delete. A checkpoint can still be posted to one.
- **A transparency-log service** gives checkpoints and inclusion proofs, not the trust state, and makes the relying party depend on it. `ledger-1` uses the same tree, so its checkpoints can be submitted to one (open question 3).
- **Timestamping each entry** (RFC 3161) shows when each existed, not that a history is whole, and puts a third party in every append. A checkpoint can be timestamped instead.
- **Signatures over the position.** A threshold of people would have to sign within one gap between entries, and every producer would wait on the writer.
- **A separate trust log.** A decision could no longer name its trust state in its own sequence, and staleness would be a rule across two logs.
- **A batch entry**, many decisions under one root. The core rules need each decision in the fold; checkpoints give most of the gain.
- **Extension kinds that move the basis.** A verifier that did not know one could compute no later state.

## Open questions

1. **System models offline.** RFC 0015 proposes that the parts travel with the package; open until it is decided.
2. **Verifying from the middle.** An export from a later position, with the trust chain and inclusion proofs, would spare a relying party the earlier entries, but leave rules over earlier record state, unique contents among them, unchecked.
3. **C2SP formats.** Whether to also emit checkpoints and cosignatures as C2SP signed notes, so that existing witnesses cosign without new code.
4. **Witnesses.** Whether they replay record entries too, whether the tenant's cosignature of a handover is required rather than optional, and who runs the first: the tenant, an auditor, operators for each other.
5. **Lapsing signatures.** An author's `until`, which a rule can enforce only against a witness's time.
6. **Withdrawal.** `supersedes` corrects a decision. Whether a core kind withdraws another record entry, an approval say, and who signs it.
7. **Several ledgers, one trust state.** A deployment that splits work across ledgers for rate keeps their trust chains in step by hand.
8. **Limits.** Proposed: 16 KiB of canonical entry, 32 KiB signed, 32 signatures, 64 approvers of 8 keys, 16 identifiers and origins.
9. **Claim registration v2** kept as a `ledger-1` ledger.
10. **Extension kinds that need approvers.** An extension kind is authorized through a service key; one that needs a threshold of people needs a core rule.
11. **The latest request.** A gate knows the order of its own requests. Whether a request names the one it follows, so that a relying party reads the latest from the ledger.

## Decision

Not made. The review period of RFC 0001, section 5, has not started. This RFC will be accepted on the maintainers' judgement alone only if it says that it had no outside review (section 7.4).

## Implementation

Not implemented.

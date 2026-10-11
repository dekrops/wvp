# Claim registration v1

Status: draft specification with a Scala reference (`modules/claim-registration`), an independent JavaScript implementation (`tooling/claim-registration.mjs`) and vectors (`test-vectors/claim-registration/v1`). A registry service that implements it exists beside the reference (`apps/claim-registry`).

Verification so far checks evidence that someone chose to submit. If the party that holds the evidence never answers, nothing records it. Claim registration closes that gap. A claim is registered **before** any evidence is asked for, at a registry both parties agreed on. The registry's signed receipt lets the claimant show anyone, without the registry's help, that the claim was made and when an answer is due.

This version covers registration (the agreement, the claim and the receipt), the respondent's response, the claimant's notice withdrawing or replacing a claim, and how the registry closes a claim: on a response, on a notice, or when the deadline has passed without a response; and disputes of a refused or answered claim, with their resolution. An audit of the log checks the registry's two rules: one open claim per unit, and the agreement's limit on open claims. A head, the registry's signed statement of where its log ends, shows whether a log is all of it, and exposes an entry the registry withheld.

## 1. Roles

| Role          | Who                                                                                                                             | Signs            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| Claimant      | The party that did the work and claims it, for example the vendor                                                               | Agreement, claim |
| Respondent    | The party obliged to answer, for example the customer holding the evidence                                                      | Agreement        |
| Registry      | A separate product, run by anyone the parties choose (ADR 0038) | Receipt          |
| Relying party | Whoever checks a registration: either party, an auditor, an arbitrator                                                          | Nothing          |

The registry is trusted for one thing: the time and order in which it received claims. It does not see the claim's inputs, and it does not decide anything about the work.

## 2. What makes a claim oblige anyone

A claim obliges the respondent to answer only if all of these hold:

- it is made under an **agreement both parties signed**;
- it is received by the **registry the agreement names**;
- it is received while the agreement is in force.

Anyone can register anything with a registry. Without the respondent's signature on the agreement it obliges nobody, and verification refuses it. This is the protection against claims sent only to impose obligations.

## 3. Objects

JSON shapes follow the Verified wire conventions ([evidence statement v1](../../../docs/spec/evidence-statement-v1.md)). UUIDs and tenants are `{ "value": … }`, times are `{ "value": "<instant>" }`, hashes are `{ "algorithm", "hex" }`, and an absent option is `null`. Times use the canonical instant spelling. Every object is decoded only if re-encoding it gives exactly the received text, byte for byte. Integers are within ±(2^53 − 1), and instants have a four-digit year, so that every implementation represents them exactly.

### 3.1 Agreement

`{ "agreement": {…}, "signatures": { "claimant": Signature, "respondent": Signature } }`, where `agreement` has exactly:

| Member                    | Meaning                                                                                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `protocol`                | `verified-claim-registration-v1`                                                                                                                             |
| `id`                      | Agreement ID (UUID)                                                                                                                                          |
| `tenant`                  | The respondent's tenant at Verified, used in work-unit identities                                                                                            |
| `contract`                | `{ id, version, digest }`: the compiled contract ([Work Contract Language 1](../../work-contract/v1/SPEC.md)). `digest` is the digest a WVP v0.2 claim names |
| `scope`                   | `{ scope, operation, identity }`: which work counts as one unit ([work-unit identity v1](../../work-unit/v1/SPEC.md), section 2)                             |
| `unitKey`                 | Commitment to the parties' 32-byte unit key: `SHA-256("verified:work-unit-key:v1\n" ‖ key)`                                                                  |
| `claimant`, `respondent`  | The two parties (UUIDs)                                                                                                                                      |
| `registry`                | The registry that receives claims, by name                                                                                                                   |
| `respondWithinSeconds`    | How long the respondent has to answer a claim, counted from the registry's receipt                                                                           |
| `openClaimLimit`          | How many claims may be open at once. Enforced by the registry, and checked by an [audit](#audit)                                                             |
| `validFrom`, `validUntil` | When claims may be received. `validUntil` may be `null`                                                                                                      |

Each party signs the same signing input, `"verified:claim-agreement:v1\n" ‖ canonical(agreement)`. A `Signature` is `{ scheme: "Ed25519", keyId, encoded }`, with `encoded` the standard base64 of the 64-byte signature.

Response windows and limits belong to the agreement, not to the contract language. The language has no durations, and its digest and semantics are unchanged.

### 3.2 Claim

`{ "claim": {…}, "signature": Signature }`, signed by the claimant over `"verified:claim-commitment:v1\n" ‖ canonical(claim)`. `claim` has exactly:

| Member      | Meaning                                                                                                                                                          |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `protocol`  | `verified-claim-registration-v1`                                                                                                                                 |
| `id`        | Claim ID (UUID). A later WVP v0.2 package for this claim uses the same ID                                                                                        |
| `agreement` | SHA-256 of the canonical agreement (the unsigned object)                                                                                                         |
| `inputs`    | SHA-256 of the canonical JSON object of the claim's input values, the `inputs` member of a WVP v0.2 claim. The values travel to the respondent, not the registry |
| `unit`      | The work unit's nullifier, `{ "algorithm": "hmac-sha-256", hex }`, derived under the parties' unit key ([section 5](#5-the-unit))                                |
| `claimedAt` | When the claimant says it made the claim. Not authenticated                                                                                                      |

### 3.3 Receipt

`{ "receipt": {…}, "signature": Signature }`, signed by the registry over `"verified:claim-receipt:v1\n" ‖ canonical(receipt)`. `receipt` has exactly:

| Member       | Meaning                                                                            |
| ------------ | ---------------------------------------------------------------------------------- |
| `protocol`   | `verified-claim-registration-v1`                                                   |
| `registry`   | The registry's name                                                                |
| `sequence`   | The entry's position in the registry's log, from 0                                 |
| `previous`   | SHA-256 of the previous entry's canonical receipt, or `null` exactly at sequence 0 |
| `claim`      | SHA-256 of the canonical claim (the unsigned object)                               |
| `receivedAt` | When the registry received the claim, by the registry's clock                      |
| `respondBy`  | `receivedAt` plus the agreement's `respondWithinSeconds`                           |

### 3.4 Response

`{ "response": {…}, "signature": Signature }`, signed by the agreement's respondent over `"verified:claim-response:v1\n" ‖ canonical(response)`. `response` has exactly:

| Member        | Meaning                                                                        |
| ------------- | ------------------------------------------------------------------------------ |
| `protocol`    | `verified-claim-registration-v1`                                               |
| `claim`       | SHA-256 of the canonical claim it answers                                      |
| `answer`      | `{ "Evidence": { "package": <SHA-256> } }` or `{ "Refused": { "reason": … } }` |
| `respondedAt` | When the respondent says it responded. Not authenticated                       |

`Evidence.package` is the package commitment of the WVP v0.2 package that holds the evidence. The package goes to whoever verifies the claim, not to the registry.

A refusal gives one reason, so that it can be checked and disputed rather than only recorded:

| Reason                                 | Meaning                                                                        |
| -------------------------------------- | ------------------------------------------------------------------------------ |
| `{ "NotUnderAgreement": {} }`          | The claim is not work under the agreement it names                             |
| `{ "WrongUnit": {} }`                  | The claim's unit is not the nullifier of its inputs ([section 5](#5-the-unit)) |
| `{ "Duplicate": { "of": <SHA-256> } }` | The same work was already claimed, by the claim with this digest               |
| `{ "Other": { "text": <non-empty> } }` | Anything else, stated                                                          |

### 3.5 Closure

`{ "closure": {…}, "signature": Signature }`, signed by the registry over `"verified:claim-closure:v1\n" ‖ canonical(closure)`. A closure is an entry of the registry's log, like a receipt, and has exactly:

| Member                                                  | Meaning                                                                                                                                                                                                    |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `protocol`, `registry`, `sequence`, `previous`, `claim` | As in a receipt; `claim` is the claim it closes                                                                                                                                                            |
| `recordedAt`                                            | When the registry recorded the closure, by its clock                                                                                                                                                       |
| `closing`                                               | `{ "Responded": { "response": <SHA-256> } }`, `{ "Expired": {} }`, `{ "Withdrawn": { "notice": <SHA-256> } }` or `{ "Superseded": { "notice": <SHA-256> } }`: the canonical response or notice it rests on |

A claim is closed by the respondent's response, evidence or refusal, recorded by the deadline; or by the registry recording, after the deadline, that none came. Evaluation reads no clock, so expiry is an entry the registry writes when it next processes the claim, carrying its own time. A response recorded after the deadline does not close a claim. Late evidence is verified on its own and never changes what the log says. The claimant can also close its own claim, while it is open or after evidence was offered, by a notice ([section 3.6](#36-notice)).

### 3.6 Notice

`{ "notice": {…}, "signature": Signature }`, signed by the agreement's claimant over `"verified:claim-notice:v1\n" ‖ canonical(notice)`. `notice` has exactly:

| Member     | Meaning                                                                                |
| ---------- | -------------------------------------------------------------------------------------- |
| `protocol` | `verified-claim-registration-v1`                                                       |
| `claim`    | SHA-256 of the canonical claim the notice is about                                     |
| `action`   | `{ "Withdraw": {} }`, or `{ "Supersede": { "by": <SHA-256 of the replacing claim> } }` |
| `issuedAt` | When the claimant says it issued the notice. Not authenticated                         |

A withdrawal ends the claim. A supersession ends it and names a corrected claim for the same work, under the same agreement, which the registry registers as its very next entry, so that nothing can take the unit in between.

### 3.7 Dispute terms

`{ "terms": {…}, "signatures": { "claimant": Signature, "respondent": Signature } }`, signed by both parties of an agreement over `"verified:claim-dispute-terms:v1\n" ‖ canonical(terms)`. They sit beside the agreement, like the unit scope, so that the agreement and its digest are unchanged. `terms` has exactly:

| Member                 | Meaning                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------- |
| `protocol`             | `verified-claim-registration-v1`                                                                     |
| `agreement`            | SHA-256 of the canonical agreement the terms belong to                                               |
| `disputeWithinSeconds` | How long after a claim is closed a dispute of it may be recorded                                     |
| `resolver`             | The party who resolves disputes (UUID), neither the claimant nor the respondent; or `null`, for none |

Without terms, a claim cannot be disputed.

### 3.8 Dispute

`{ "dispute": {…}, "signature": Signature }`, signed by the party that opens it over `"verified:claim-dispute:v1\n" ‖ canonical(dispute)`. `dispute` has exactly:

| Member     | Meaning                                                                                                                                |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `protocol` | `verified-claim-registration-v1`                                                                                                       |
| `claim`    | SHA-256 of the canonical claim disputed                                                                                                |
| `terms`    | SHA-256 of the canonical dispute terms it is opened under                                                                              |
| `by`       | The party that opens it: the agreement's claimant or respondent                                                                        |
| `ground`   | `{ "RefusalUnfounded": {} }`, `{ "EvidenceIncomplete": {} }`, `{ "DecisionContested": {} }`, or `{ "Other": { "text": <non-empty> } }` |
| `openedAt` | When the party says it opened the dispute. Not authenticated                                                                           |

A refused claim can be disputed by its claimant, and a claim answered with evidence by either party, once. An open claim has nothing to dispute yet; an expiry follows from the registry's clock; a withdrawal or supersession is the claimant's own act.

### 3.9 Resolution

`{ "resolution": {…}, "signatures": … }`, over `"verified:claim-resolution:v1\n" ‖ canonical(resolution)`. `resolution` has exactly `protocol`, `dispute` (SHA-256 of the canonical dispute it resolves), `outcome` (`{ "Upheld": {} }`, the disputing party's position stands, or `{ "Rejected": {} }`) and `resolvedAt`. `signatures` is either `{ "Resolver": { "signature": Signature } }`, by the resolver the dispute terms name, or `{ "Settlement": { "claimant": Signature, "respondent": Signature } }`, by both parties together. A settlement is always possible; without a resolver it is the only way to end a dispute. A dispute nobody resolves stays open: the registry cannot force a resolution.

### 3.10 Dispute record

`{ "disputeRecord": {…}, "signature": Signature }`, signed by the registry over `"verified:claim-dispute-record:v1\n" ‖ canonical(record)`. A dispute record is an entry of the registry's log, like a receipt or a closure, with `protocol`, `registry`, `sequence`, `previous`, `claim` and `recordedAt` as in a closure, and `step`: `{ "Opened": { "dispute": <SHA-256> } }` or `{ "Resolved": { "resolution": <SHA-256> } }`.

**A dispute never changes a claim's own state.** A refused claim stays refused in the log; the dispute and its resolution are recorded beside it, and whoever acts on the claim, such as a billing system, reads both. Nothing recorded is rewritten.

### 3.11 Head

`{ "head": {…}, "signature": Signature }`, signed by the registry over `"verified:claim-log-head:v1\n" ‖ canonical(head)`, with a key that signs its entries. `head` has exactly:

| Member     | Meaning                                                                                                                 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------- |
| `protocol` | `verified-claim-registration-v1`                                                                                        |
| `registry` | The registry's name                                                                                                     |
| `size`     | How many entries the log has                                                                                            |
| `last`     | SHA-256 of the last entry's canonical object, as the next entry's `previous` would name it; or `null` exactly at size 0 |
| `issuedAt` | When the registry issued the head, by the clock that dates its entries                                                  |

A head is not an entry of the log and changes nothing in it. It is the registry's statement that, at `issuedAt`, its log was these `size` entries and no more. A registry issues heads as often as it is asked.

The eleven signing domains differ, so a signature for one kind of object is never valid for another, or for any other Verified object.

## 4. Verification

The relying party supplies its own trust configuration, never data received with a claim:

- **party keys:** `{ keyId, algorithm, publicKey, party, validFrom, validUntil, revokedAt }`;
- **registry keys:** the same, with `registry` in place of `party`.

`publicKey` is the base64 DER SubjectPublicKeyInfo of an Ed25519 key. Trusting a registry key is the relying party's decision that this registry keeps honest time and order.

Checks run in this order and stop at the first failure, so every implementation reports the same code for the same input:

1. Each object is well formed, its text is canonical, and its integers and years are in range — `MALFORMED`.
2. Every `protocol` is `verified-claim-registration-v1` — `UNSUPPORTED_PROTOCOL`.
3. `contract.digest`, `unitKey`, the claim's `agreement` and `inputs`, and the receipt's `claim` and `previous` are SHA-256 commitments, and `unit` is an HMAC-SHA-256 nullifier. Each is 64 lowercase hex digits — `MALFORMED_COMMITMENT`.
4. The agreement is sound: two different parties, `respondWithinSeconds > 0`, `openClaimLimit > 0`, a non-empty registry, contract ID and version, a scope with a non-empty operation and distinct identifying inputs, and `validUntil` after `validFrom` — `AGREEMENT_INVALID`.
5. The claimant's agreement signature, then the respondent's. Each key is known (`UNKNOWN_KEY`) and Ed25519 (`UNSUPPORTED_ALGORITHM`), belongs to that party (`PARTY_MISMATCH`) and is valid at `validFrom` (`KEY_NOT_VALID`), and the signature verifies (`SIGNATURE_INVALID`).
6. The claim names this agreement — `AGREEMENT_MISMATCH`.
7. The claim's signature, as in step 5, by the claimant's key, valid at `claimedAt`.
8. The receipt names this claim — `CLAIM_MISMATCH`.
9. The receipt is from the agreement's registry — `REGISTRY_MISMATCH`.
10. `previous` is `null` exactly at sequence 0, and the sequence is not negative — `CHAIN_INVALID`.
11. The receipt's signature, as in step 5, by a key of that registry (`REGISTRY_MISMATCH` for another registry's key), valid at `receivedAt`.
12. `validFrom ≤ receivedAt < validUntil` — `AGREEMENT_NOT_IN_FORCE`.
13. `claimedAt ≤ receivedAt` — `CLAIMED_AFTER_RECEIPT`.
14. `respondBy = receivedAt + respondWithinSeconds` — `DEADLINE_MISMATCH`.

A key is valid at `t` when `validFrom ≤ t < validUntil` and `t < revokedAt`. As with evidence statements, asserted times (`validFrom`, `claimedAt`) are not authenticated. The registry's `receivedAt` is authenticated, by the registry's signature.

### What a verified registration establishes

The claim with this ID, committing to these inputs and this unit, was made under an agreement both parties signed. The registry they named received it at `receivedAt`, as entry `sequence` of its log, and the respondent must answer by `respondBy`.

### What it does not establish

- **That the claim is true.** Whether the work was done is decided later, by verifying evidence against the contract.
- **That the registry applied its own rules:** that no earlier open claim held the same unit, or that the open-claim limit was respected. Both need the registry's log from its start: see [audit](#audit).
- **That nothing was removed from the registry's log.** One receipt shows one entry. A run of the log, checked as in [log segments](#log-segments), shows more.
- **That the log shown is all of it.** A registry can leave off the end. A [head](#heads) shows where the log ended at a given time.
- **That the unit is derived correctly from the inputs.** Only holders of the unit key can check that ([section 5](#5-the-unit)).

### Log segments

A registry publishes its log as receipts. A relying party can check a run of them, and check a receipt it holds against that run, without trusting the registry. Neither needs the claims, only the receipts.

**A segment** is a non-empty list of receipts in the order received, optionally with an **anchor**: an entry verified before, which the segment continues. Checks run in this order and stop at the first failure:

1. An empty list — `MALFORMED`.
2. Each receipt, and the anchor, on its own: structure and range (`MALFORMED`), protocol (`UNSUPPORTED_PROTOCOL`), commitments (`MALFORMED_COMMITMENT`), position (`CHAIN_INVALID`), and the signature of a key of the registry the receipt names, valid at its `receivedAt` (`UNKNOWN_KEY`, `UNSUPPORTED_ALGORITHM`, `REGISTRY_MISMATCH`, `KEY_NOT_VALID`, `SIGNATURE_INVALID`).
3. All receipts and the anchor are from one registry — `MIXED_REGISTRIES`.
4. No two different receipts for one position — `EQUIVOCATION`.
5. Positions strictly ascending — `REORDERED`.
6. Without an anchor, the segment starts at position 0 — `GENESIS_INVALID`.
7. From the anchor, if any, each entry is at the next position (`GAP`) and names the entry before it as `previous` (`PREVIOUS_MISMATCH`).
8. No entry was received before the one before it — `TIME_REVERSED`.
9. No claim appears at two positions, the anchor included — `DUPLICATE_CLAIM`.

A verified segment establishes that its receipts are consecutive entries of the registry's log, in order, with nothing inserted, removed or altered between the first and the last. It does not establish anything after the last: on its own, a segment does not show a truncated tail. A [head](#heads) does.

**A held receipt**, such as the one a claimant was given, is checked on its own as in step 2, must name the segment's registry (`REGISTRY_MISMATCH`), and then is one of:

| Outcome        | Meaning                                                                                                                                           |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `INCLUDED`     | The entry at its position is this receipt                                                                                                         |
| `NOT_COVERED`  | The segment does not reach its position                                                                                                           |
| `EQUIVOCATION` | The segment has another entry at its position. The registry signed both: the two receipts together prove it rewrote its log, whatever it now says |

This is what keeps a registry from silently dropping a claim. Removing an entry and renumbering the rest gives a log that verifies on its own. But every claimant whose receipt came after the removed entry now holds a signed receipt that the log contradicts.

The log has three kinds of entry, receipts, closures and dispute records, told apart by their one member besides `signature`. All are checked the same way in step 2, with `recordedAt` in place of `receivedAt` and the digest a closure or dispute record names among its commitments. Each is a held entry like any other. Step 9 counts registrations only: a claim is registered once and closed once.

### Audit

An audit reads the log **from its first entry** and finds each registered claim's state. It is given the entries, and the agreements, claims, responses, notices, dispute terms, disputes and resolutions the log names. Each document is found by the digest the log names, compared on the received JSON. Documents the log does not name are ignored. Checks run in this order and stop at the first failure:

1. The entries are a segment without an anchor, as above. An audit needs the start of the log (`GENESIS_INVALID`).
2. Each entry, in log order:
   - **A receipt.** If the entry before it superseded a claim, this receipt registers the replacing claim (`SUPERSESSION_INCOMPLETE`). The claim with that digest is supplied (`MISSING_CLAIM`), and so is the agreement the claim names (`MISSING_AGREEMENT`). The three verify as a registration (section 4, with its codes). A replacing claim is under the same agreement as the claim it replaces (`SUPERSESSION_INVALID`). Then the registry's rules, against the claims registered before it:
     - No earlier claim under the same unit key with the same `unit` **holds** it (`UNIT_HELD`). A claim holds its unit while it is `OPEN` or `ANSWERED`, while a dispute of it is open, or, once refused, if the claimant's dispute of the refusal was upheld. A refusal, an expiry, a withdrawal or a supersession otherwise releases a unit; any other resolved dispute leaves the claim's state to decide. Evidence offered keeps it held, because the work was claimed and evidenced.
     - Fewer than the agreement's `openClaimLimit` claims under the same agreement are `OPEN` (`LIMIT_EXCEEDED`).

     The claim is now `OPEN`.

   - **A closure.** The entry before it did not supersede a claim (`SUPERSESSION_INCOMPLETE`). The claim was registered at an earlier position (`CLOSURE_WITHOUT_REGISTRATION`) and is still open, or, for a withdrawal or supersession, open or answered (`ALREADY_CLOSED`). A withdrawal or supersession needs no dispute of the claim to be open (`DISPUTE_OPEN`): the dispute is settled first, since otherwise it would hold a unit nothing could release.
     - `Expired`: `recordedAt` is after the claim's `respondBy` (`EXPIRED_EARLY`). The claim is `EXPIRED`.
     - `Responded`: the response with that digest is supplied (`MISSING_RESPONSE`). It is well formed and in range (`MALFORMED`), of this protocol (`UNSUPPORTED_PROTOCOL`), and its `claim`, `package` and `Duplicate.of` are SHA-256 commitments (`MALFORMED_COMMITMENT`). An `Other` reason is not empty (`RESPONSE_INVALID`). It answers this claim (`CLAIM_MISMATCH`). It is signed by the agreement's respondent as in step 5 of section 4, with a key valid at `respondedAt`. `respondedAt ≤ recordedAt` (`RESPONDED_AFTER_RECORD`), and `recordedAt ≤ respondBy` (`LATE_RESPONSE`). The claim is `ANSWERED` for evidence, or `REFUSED`.
     - `Withdrawn` or `Superseded`: the notice with that digest is supplied (`MISSING_NOTICE`). It is well formed and in range (`MALFORMED`), of this protocol (`UNSUPPORTED_PROTOCOL`), and its `claim` and `by` are SHA-256 commitments (`MALFORMED_COMMITMENT`). Its action is the closure's: `Withdraw` for `Withdrawn`, `Supersede` for `Superseded` (`NOTICE_MISMATCH`). It is about this claim (`CLAIM_MISMATCH`). It is signed by the agreement's claimant as in step 5 of section 4, with a key valid at `issuedAt`, and `issuedAt ≤ recordedAt` (`NOTICE_AFTER_RECORD`). The claim is `WITHDRAWN` or `SUPERSEDED`.
   - **A dispute record.** The entry before it did not supersede a claim (`SUPERSESSION_INCOMPLETE`). The claim was registered at an earlier position (`DISPUTE_WITHOUT_CLAIM`).
     - `Opened`: the claim is `REFUSED` or `ANSWERED` (`NOT_DISPUTABLE`) and was never disputed (`ALREADY_DISPUTED`). The dispute with that digest is supplied (`MISSING_DISPUTE`); it is well formed and in range (`MALFORMED`), of this protocol (`UNSUPPORTED_PROTOCOL`), its `claim` and `terms` are SHA-256 commitments (`MALFORMED_COMMITMENT`), an `Other` ground is not empty (`DISPUTE_INVALID`), and it is about this claim (`CLAIM_MISMATCH`). The terms with that digest are supplied (`MISSING_TERMS`); they are well formed (`MALFORMED`), of this protocol (`UNSUPPORTED_PROTOCOL`), with a SHA-256 `agreement` (`MALFORMED_COMMITMENT`) that is the claim's (`AGREEMENT_MISMATCH`), a positive window and a resolver who is neither party (`TERMS_INVALID`), signed by the claimant and then the respondent as in step 5 of section 4, with keys valid at the agreement's `validFrom`. The dispute's `by` is the claimant, or the respondent if the claim is `ANSWERED`: only the claimant disputes a refusal (`PARTY_MISMATCH`), and it is signed by that party with a key valid at `openedAt`. `openedAt ≤ recordedAt` (`DISPUTED_AFTER_RECORD`), and `recordedAt` is at most `disputeWithinSeconds` after the claim's closure was recorded (`LATE_DISPUTE`). A refusal released the unit, and an open dispute holds it again: if the claim does not hold its unit, no other claim may hold it (`UNIT_HELD`). The dispute is `OPEN`.
     - `Resolved`: the claim's dispute is open (`NO_OPEN_DISPUTE`). The resolution with that digest is supplied (`MISSING_RESOLUTION`); it is well formed and in range (`MALFORMED`), of this protocol (`UNSUPPORTED_PROTOCOL`), with a SHA-256 `dispute` (`MALFORMED_COMMITMENT`) that is the open dispute (`DISPUTE_MISMATCH`). A resolver's resolution needs terms that name one (`NO_RESOLVER`) and is signed by the resolver; a settlement is signed by the claimant and then the respondent; each key valid at `resolvedAt`, as in step 5 of section 4. `resolvedAt ≤ recordedAt` (`RESOLVED_AFTER_RECORD`). The dispute is `UPHELD` or `REJECTED`.
3. The log does not end on a supersession whose replacement is not registered (`SUPERSESSION_INCOMPLETE`).

The result lists every registered claim in log order, with its digest, ID, position, `respondBy` and state: `OPEN`, `ANSWERED`, `REFUSED`, `EXPIRED`, `WITHDRAWN` or `SUPERSEDED`; and, for a disputed claim, its dispute: `OPEN`, `UPHELD` or `REJECTED`. All states but `OPEN` and `ANSWERED` are final: nothing in the log changes them, disputes included. A claim with an open dispute is not ready to be acted on, whatever its state.

An audit establishes that the log, up to its last entry, is a consistent history: every claim was registered under an agreement both parties signed, and closed at most once: by the respondent in time, by expiry after the deadline, or by the claimant. A state is the log's state, not a verification result. `ANSWERED` means evidence was offered, not that it supports the claim. That is decided by verifying the package.

### Heads

A head ([section 3.11](#311-head)) is checked on its own, and then against what a relying party holds: an entry, a verified segment, or another head. Each check is between two things the registry signed, so a contradiction is proof against the registry, whatever it now says.

**A head on its own.** Checks run in this order and stop at the first failure: structure and range (`MALFORMED`), protocol (`UNSUPPORTED_PROTOCOL`), `last` is a SHA-256 commitment (`MALFORMED_COMMITMENT`), `size` is not negative and `last` is `null` exactly at size 0 (`CHAIN_INVALID`), and the signature is by a key of the registry the head names, valid at `issuedAt` (`UNKNOWN_KEY`, `UNSUPPORTED_ALGORITHM`, `REGISTRY_MISMATCH`, `KEY_NOT_VALID`, `SIGNATURE_INVALID`).

**An entry against a head.** The entry is checked on its own as in log segments, step 2, and names the head's registry (`REGISTRY_MISMATCH`). Its time is its `receivedAt` or `recordedAt`. Then, in this order:

| Outcome        | When                                                                                                                                                     |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WITHHELD`     | Its position is `size` or later, and its time is before `issuedAt`. The registry had recorded it and issued a head without it                            |
| `NOT_COVERED`  | Its position is `size` or later, and its time is not before `issuedAt`: recorded since                                                                   |
| `EQUIVOCATION` | Its position is `size − 1` and it is not `last`. The registry signed two entries for one position; the outcome gives both digests, `headed` and `logged` |
| `PREDATED`     | Its position is before `size`, and its time is after `issuedAt`: the head counts an entry that was recorded only later                                   |
| `INCLUDED`     | It is `last`                                                                                                                                             |
| `COVERED`      | Its position is before `size − 1`. The head counts its position; that the entry is the one at that position needs a segment                              |

`WITHHELD` and `PREDATED` give the entry's `sequence`. An entry recorded in the same instant as the head was issued is neither.

**A segment against a head.** The segment is verified as in log segments and is the head's registry's (`REGISTRY_MISMATCH`). Each of its entries is taken against the head as above. The outcome is the first `EQUIVOCATION` among them in log order, else the first `PREDATED`, else the first `WITHHELD`. Otherwise it says where the segment ends:

| Outcome       | When                                                                                                              |
| ------------- | ----------------------------------------------------------------------------------------------------------------- |
| `BEHIND`      | The segment ends before position `size − 1`: it is not the whole log as of `issuedAt`                             |
| `NOT_COVERED` | The segment starts after position `size − 1`, and not at 0: it shows nothing about the head                       |
| `CURRENT`     | The segment ends at position `size − 1`: it is the log as of `issuedAt`, to its last entry                        |
| `AHEAD`       | The segment contains position `size − 1`, or starts at 0 after a head of size 0, and continues with later entries |

**Two heads.** Both are checked on their own and are one registry's (`REGISTRY_MISMATCH`). With the same `size` they name the same `last`, else `EQUIVOCATION`, with the first head's `last` as `headed` and the second's as `logged`. With different sizes, the smaller one was not issued after the larger one, else `WITHHELD` with the smaller `size` as `sequence`: having stated the longer log, the registry later stated a shorter one. Otherwise `CONSISTENT`.

**What a head establishes.** An audit of a log that is `CURRENT` against a head gives every claim's state as of `issuedAt`, not only up to wherever the log shown happens to end. A party that holds an entry, such as the respondent's closure, can show that a later head without it withheld it. A relying party asks for a head when it reads the log and decides how old a head it accepts.

**What it does not establish.** A head is the registry's own statement. A registry can issue an old head again, or decline to issue one. It cannot issue a head that leaves out an entry it gave someone without that entry proving it. Two relying parties that compare the heads they were given catch a registry that shows them different logs.

## 5. The unit

`unit` is the work-unit v1 nullifier of the claim, with two differences from [work-unit identity v1](../../work-unit/v1/SPEC.md):

- The key is the **parties' unit key**, pinned by the agreement's `unitKey`, not a key held by Verified.
- The scope is the agreement's `scope`, and the identifying values are the claim's inputs that the scope names, in order.

The identity is unchanged: `["work-unit-1", tenant, scope, operation, [values…]]`.

The registry holds neither the key nor the inputs, so it can compare units without learning which invoice a claim is about. Either party can check that a claim's unit belongs to its inputs, given the agreement, the claim, the input values (a canonical JSON object of strings, whose digest the claim commits to) and the unit key. Checks, in order:

1. Each is well formed and canonical, and the key is 32 bytes in lowercase hex — `MALFORMED`.
2. The claim names this agreement — `AGREEMENT_MISMATCH`.
3. The key's commitment is the agreement's `unitKey` — `UNIT_KEY_MISMATCH`.
4. The inputs are those the claim committed to — `INPUTS_MISMATCH`.
5. The inputs include every identifying input the scope names — `MISSING_INPUT`.
6. The claim's `unit` is the nullifier of those values — `UNIT_MISMATCH`.

A respondent that finds a mismatch refuses the claim with the reason `WrongUnit`, which releases the unit. The check verifies no signatures: it assumes a registration already verified as in section 4. Agreements that should share units, such as consecutive versions of one contract, use the same scope and the same unit key.

## 6. Relation to WVP v0.2

A registered claim is later verified like any other contract claim. The package's claim has the registration's claim ID, names the agreement's contract digest, and has inputs whose canonical digest is the registration's `inputs`. Linking a work record to its registration is not part of this version.

## 7. Versioning

Changing any member, encoding rule, check, check order or error code requires a new protocol version and a new vector directory. v1 vectors are never regenerated with different expectations. Unknown versions fail closed. Log segments, responses, notices, closures, disputes and audits were added to v1 while it was a draft, before any registry existed. They add objects, procedures and codes; they change no object, check or code of the registration procedure, and the earlier vectors are unchanged.

Heads were added on 2026-10-11, after v1 was published, as its first addition since (v1.1). They add one object, one signing domain, four procedures and seven outcomes: `WITHHELD`, `PREDATED`, `COVERED`, `CURRENT`, `BEHIND`, `AHEAD` and `CONSISTENT`. The outcomes `INCLUDED`, `NOT_COVERED` and `EQUIVOCATION` and every refusal code they use existed before. No object, check, check order, code or vector that existed before is changed, and an implementation without heads still conforms to everything else.

## 8. Not in this version

- **Witnesses.** Nobody is appointed to collect a registry's heads and compare them. Relying parties that exchange heads do that for themselves.
- **How a registry serves** its log, its heads and the documents it holds. That is a service's interface, not this protocol.

## 9. Conformance

`test-vectors/claim-registration/v1/vectors.json` holds the deterministic test keys, the relying party's trust configuration, the unit key and inputs of the base claim, and 28 cases. Each case gives the exact agreement, claim and receipt text and the expected outcome: the registration's facts, or the first refusal code. The Scala reference (`verified.registration.Registration`) and the JavaScript implementation (`tooling/claim-registration.mjs`) both reproduce every case. The JavaScript implementation also re-derives the base claim's unit, inputs digest and unit-key commitment. `log.json` holds 20 cases of log segments and held receipts under the same keys: each gives the receipts, the anchor and the held receipt, if any, and the segment, the inclusion outcome or the first refusal. `audit.json` holds 22 audits of whole logs with their agreements, claims and responses, and each claim's state or the first refusal. `unit.json` holds 7 unit checks. `notice.json` holds 15 audits of logs in which the claimant withdraws or replaces claims, with the notices they name. `dispute.json` holds 32 audits of logs with disputes, with the dispute terms, disputes and resolutions they name, under its own trust configuration, which adds a resolver's public test key. `head.json` holds 39 cases of heads under the keys of `vectors.json`: alone, and against a held entry, a segment or another head, each with its outcome or first refusal. The test keys are public and must never be trusted or provisioned.

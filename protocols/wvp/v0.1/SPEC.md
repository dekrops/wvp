# Work Verification Protocol v0.1

|                      |                                                                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Identifier           | `wvp-0.1`                                                                                                                              |
| Version              | 0.1                                                                                                                                    |
| Status               | Draft                                                                                                                                  |
| Depends on           | [`verified-json-v1`](../../canonical-json/v1/SPEC.md); [`verified-evidence-statement-v1`](../../../docs/spec/evidence-statement-v1.md) |
| Normative references | RFC 8032 (Ed25519); RFC 4648 (base64); FIPS 180-4 (SHA-256)                                                                            |
| Conformance          | [`test-vectors/wvp/v0.1`](../../../test-vectors/wvp/v0.1)                                                                              |

Status: draft. Identifier: `wvp-0.1`.

Implementation status: two verifiers (Scala, JavaScript) agree on the conformance vectors. One application flow produces and exports packages: order fulfilment, on synthetic data, without an issuer signature, with the evidence key held by the deployment that also verifies. Nothing else in the product produces packages.

A **package** is one file from which a second party can check, offline and without the system that produced it, that a claim about work is supported by admissible evidence under a contract. This document defines the package, the one evaluator v0.1 specifies, and exactly what verifying a package establishes.

The protocol builds on two existing specifications and does not redefine them:

- [Verified Evidence Statement v1](../../../docs/spec/evidence-statement-v1.md): who asserted a piece of evidence, under which key and authority.
- `verified-json-v1` canonicalization ([Canonical JSON](../../canonical-json/v1/SPEC.md)): the byte form everything is hashed in.

## 1. Objects

| Object     | Meaning                                                                            |
| ---------- | ---------------------------------------------------------------------------------- |
| Claim      | An actor's assertion that work with a given outcome occurred, naming its evidence. |
| Contract   | What counts as that work: subject, expected outcome, a transition rule, validity.  |
| Statements | Signed evidence statements, each with the body it commits to.                      |
| Inputs     | The explicit parameters of one evaluation, including its time.                     |
| Decision   | What an evaluator concludes from the four objects above.                           |

JSON shapes follow the existing Verified wire conventions: identifiers are `{"value": "<uuid>"}`, timestamps are `{"value": "<ISO-8601 UTC>"}`, digests are `{"algorithm": "sha-256", "hex": "<64 lowercase hex>"}`, and an enumeration case is an object with the case name as its only key.

Time is never read from a clock. The evaluation time is `inputs.evaluatedAt`. Two times are equal when they denote the same instant.

Every object is closed: a member this document does not list, an enumeration case it does not name, a case carrying members it does not have, and a value of the wrong type are all refused, at any depth. Integers fit 32 bits.

| Object     | Members                                                                                                                                                                                  |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claim      | `id`, `contractId`, `claimant`, `subject`, `outcome`, `evidence` (IDs), `occurredAt`, `submittedAt`, `provenance`, `supersedes` (ID or null); optionally `contractSnapshotHash` (digest) |
| Contract   | `id`, `version`, `workType`, `subject`, `expectedOutcome`, `policy`, `parties` (IDs), `validity`                                                                                         |
| Policy     | `id`, `version`, `rule` (`allowedFrom`: states, `to`: state), `requiredEvidence` (evidence kinds)                                                                                        |
| Subject    | `system`, `kind`, `key` (text)                                                                                                                                                           |
| Validity   | `from`, `until` (time or null)                                                                                                                                                           |
| Version    | `major`, `minor`, `patch`                                                                                                                                                                |
| Provenance | `source` (`system`, `observationId`), `witness`, `trust`, `observedAt`, `ingestedAt`, `transformations` (`name`, `version`, `inputHashes`), `causedBy` (IDs)                             |

| Enumeration   | Cases                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------ |
| State         | `Created`, `Approved`, `Shipped`, `Cancelled`                                                    |
| Outcome       | `OrderRecorded`; `OrderReached` with `state`; `GoodsIssued` with `orderItem`, `quantity`, `unit` |
| Work type     | `OrderFulfillment`, `OrderCapture`                                                               |
| Trust         | `Unauthenticated`, `SourceAuthenticated`, `Signed`, `HumanAttested`                              |
| Evidence kind | As in Evidence Statement v1                                                                      |

`contractSnapshotHash`, when present, is part of the claim and therefore of its commitment. It is never added or removed when a package is written.

## 2. Package

A package is the `verified-json-v1` encoding of an object with exactly these members:

| Member              | Meaning                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| `manifest`          | `packageVersion` 2, `protocol` `wvp-0.1`, `canonicalVersion`, and `files`. |
| `packageCommitment` | SHA-256 of the canonical manifest.                                         |
| `packageId`         | `wvp:sha-256:<hex of packageCommitment>`.                                  |
| `files`             | The components: `path` and JSON `content`, in the order below.             |
| `signatures`        | Zero or more issuer signatures over the decision (section 6).              |

`manifest.files` lists `path` and `hash` for each component, where `hash` is the SHA-256 of the component's canonical content. Components, in this order and with no others:

| Path                       | Content                                                            |
| -------------------------- | ------------------------------------------------------------------ |
| `claim.json`               | The claim.                                                         |
| `contract.json`            | The contract.                                                      |
| `decision.json`            | The decision (section 5).                                          |
| `evidence/bodies.json`     | Array of `{id, body}`, one per statement, in statement order.      |
| `evidence/statements.json` | Array of signed statements, ordered by evidence ID as a string.    |
| `inputs.json`              | `tenant`, `packageId`, `ingestedAt`, `assembledAt`, `evaluatedAt`. |

`inputs.packageId` identifies the admitted evidence set; it is unrelated to the package's own `packageId`.

A body is one of these cases, and no other:

| Body case          | Members                                 |
| ------------------ | --------------------------------------- |
| `StateTransition`  | `subject`, `from`, `to`, `at`           |
| `ExternalArtifact` | `mediaType`, `location`, `digest`       |
| `HumanAttestation` | `subject`, `statement`, `witness`, `at` |
| `Redacted`         | `originalCommitment`, `disclosedFact`   |
| `RetainedMetadata` | `subject`, `originalKind`               |

Richer observations belong to evaluators this version does not specify. A package carrying one is refused.

No component is an event log. Adapters may produce one elsewhere; a package never requires it.

## 3. Admission

The statements are verified and admitted exactly as [Evidence Statement v1](../../../docs/spec/evidence-statement-v1.md) defines, with `inputs.tenant`, `inputs.packageId`, `inputs.ingestedAt`, `inputs.assembledAt` and the claim's evidence list. Its rejection codes are used unchanged.

An admitted statement is referred to below by its statement fields (`id`, `kind`, `subject`, `source`, `observedAt`) and its body.

## 4. The order-transition evaluator

Evaluator `order-transition`, specification `1`. It applies to contracts whose rule is `allowedFrom` (a set of states) and `to` (the target state).

Write `C` for the claim, `K` for the contract, `T` for `inputs.evaluatedAt`.

### 4.1 Input conditions

All must hold. If one fails the inputs do not belong together: the result is the refusal `INPUT_MISMATCH`, not a decision about the claim.

1. At least one statement was admitted.
2. `C.contractId` equals `K.id`.
3. `C.subject` equals `K.subject`.
4. `C.outcome` equals `K.expectedOutcome`.
5. `K.validity` contains `C.occurredAt`: `validity.from` ≤ `C.occurredAt`, and `C.occurredAt` < `validity.until` if `until` is present.
6. `T` ≥ `C.submittedAt`.
7. `T` ≥ `inputs.assembledAt`.

### 4.2 Qualifying transitions

An admitted statement is a **qualifying transition** if all of these hold:

1. Its `kind` is `StateTransition` and its body is a state transition `{subject, from, to, at}`.
2. The body's `subject`, the statement's `subject` and `C.subject` are equal.
3. The statement's `source.system` equals `C.subject.system`.
4. The body's `at`, the statement's `observedAt` and `C.occurredAt` are equal.
5. `K.validity` contains that time.
6. `inputs.ingestedAt` ≥ that time.
7. `T` ≥ `inputs.ingestedAt`.

A statement that does not qualify is neither support nor contradiction. It is ignored, however authentic it is.

### 4.3 Conditions and decision

| Condition                  | Holds when                                                                            | Evidence listed        |
| -------------------------- | ------------------------------------------------------------------------------------- | ---------------------- |
| `CONTRADICTING_TRANSITION` | Some qualifying transition has `to` ≠ `K.policy.rule.to`.                             | Those statements' IDs. |
| `OUTCOME_IS_TARGET`        | `K.expectedOutcome` is "order reached `K.policy.rule.to`".                            | None.                  |
| `REQUIRED_EVIDENCE`        | For every kind in `K.policy.requiredEvidence`, some admitted statement has that kind. | None.                  |
| `SUPPORTING_TRANSITION`    | Some qualifying transition has `from` in `allowedFrom` and `to` = `K.policy.rule.to`. | Those statements' IDs. |

The decision is:

1. `CONTRADICTED` if `CONTRADICTING_TRANSITION` holds;
2. otherwise `SUPPORTED` if `OUTCOME_IS_TARGET`, `REQUIRED_EVIDENCE` and `SUPPORTING_TRANSITION` all hold;
3. otherwise `UNDETERMINED`.

A contradiction outweighs support. A decision is about the claim under this evidence; it is not a statement that the source was right.

### 4.4 Relationship to the implementation's statuses and the formal model

| Protocol       | Reference implementation status                                                                          |
| -------------- | -------------------------------------------------------------------------------------------------------- |
| `SUPPORTED`    | Supported                                                                                                |
| `CONTRADICTED` | Contradicted                                                                                             |
| `UNDETERMINED` | InsufficientEvidence; for other evaluators also AwaitingObservation, SourceUnavailable, Pending, Expired |

`Disputed` and `IntegrityFailure` are not decisions about a claim and have no representation in v0.1. A package whose evidence fails integrity is refused.

`formal/lean/Verified/Order.lean` states a predicate `Satisfies` for one piece of evidence. `SUPPORTED` implies that predicate for a supporting statement. The formal model is narrower than this section: it has no contradiction, no required-evidence condition and no conditions 6 and 7 of 4.1. Those are specified here and covered by vectors only.

## 5. Decision object

`decision.json` has exactly these members:

| Member        | Meaning                                                                                                                                |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `protocol`    | `wvp-0.1`.                                                                                                                             |
| `evaluator`   | `{"name": "order-transition", "specification": "1"}`.                                                                                  |
| `decision`    | `SUPPORTED`, `CONTRADICTED` or `UNDETERMINED`.                                                                                         |
| `conditions`  | The four conditions of 4.3, ordered by `id`: `{id, holds, evidence}`, evidence IDs ordered as strings.                                 |
| `commitments` | SHA-256 of the canonical `claim`, `contract`, and `inputs`; `evidence` is the digest of the evidence manifest that admission produces. |

It contains no result identifier, no identity of the evaluating party and no time other than through the `inputs` commitment. Two verifiers given the same package compute the same bytes.

The evaluator is named, not hashed. A hash of an implementation would suggest a guarantee that does not exist; conformance is established by the vectors.

## 6. Issuer signature

Optional. A signature is `{scheme, keyId, encoded}` with scheme `Ed25519`, over the bytes `verified:wvp-decision:v0.1\n` followed by the canonical decision. It counts only if the verifier's registry holds the key, for `inputs.tenant`, with the source `wvp-decision` among the key's sources, valid at `inputs.evaluatedAt`.

A signature says who stands behind a decision. It does not replace reproducing it.

## 7. Verifying a package

Checks run in this order and stop at the first failure, which is the result. A verifier reports the same code as any other for the same package.

| Step | Check                                                                                                                                                             | Refusal               |
| ---- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| 1    | The text is the canonical encoding of a JSON value.                                                                                                               | `NOT_CANONICAL`       |
| 2    | `packageVersion` is 2, `protocol` is `wvp-0.1`, `canonicalVersion` is `verified-json-v1`.                                                                         | `UNSUPPORTED_VERSION` |
| 3    | The package has exactly the members of section 2 and nothing else.                                                                                                | `MALFORMED_COMPONENT` |
| 4    | The component paths, in `files` and in the manifest, are exactly those of section 2.                                                                              | `COMPONENT_SET`       |
| 5    | Every component's digest equals its manifest entry.                                                                                                               | `COMPONENT_DIGEST`    |
| 6    | `packageCommitment` and `packageId` are as defined.                                                                                                               | `COMMITMENT_MISMATCH` |
| 7    | Every component is well formed at every depth (section 1) and every body is a listed case; bodies and statements carry the same IDs in the same, ascending order. | `MALFORMED_COMPONENT` |

With steps 1 to 7 passed, **integrity** is established. A verifier without a trust registry stops here and reports that signatures were not checked and the decision was not reproduced.

| Step | Check                                                            | Refusal                    |
| ---- | ---------------------------------------------------------------- | -------------------------- |
| 8    | The decision names this protocol and the evaluator of section 4. | `UNSUPPORTED_EVALUATOR`    |
| 9    | Each statement verifies under the registry, in order.            | The statement's code       |
| 10   | Admission (section 3).                                           | The admission code         |
| 11   | Input conditions (4.1).                                          | `INPUT_MISMATCH`           |
| 12   | The decision computed by 4.2 to 5 equals `decision.json`.        | `DECISION_MISMATCH`        |
| 13   | Every issuer signature counts (section 6).                       | `ISSUER_SIGNATURE_INVALID` |

## 8. What verification establishes

A verifier reports each property separately and never a single "valid".

| Property            | Established by                                         |
| ------------------- | ------------------------------------------------------ |
| Package integrity   | Steps 1 to 7.                                          |
| Evidence signatures | Step 9.                                                |
| Signer authority    | Step 9, under the registry the relying party supplied. |
| Decision reproduced | Steps 10 to 12.                                        |
| Issuer signature    | Step 13: established, or absent.                       |
| Source truthfulness | Nothing. No check can establish it.                    |

A reproduced `CONTRADICTED` or `UNDETERMINED` is a successful verification of a package whose claim is not supported.

The relying party supplies its own trust: which keys it accepts and for which sources, whether the contract is one it agrees to be bound by, and this document.

## 9. Versioning

A change to any encoding, rule, order of checks or refusal code is a new protocol or specification version. Published vectors are never regenerated. Unknown versions are refused, never interpreted (ADR 0024).

## 10. Conformance

`test-vectors/wvp/v0.1/` holds self-contained vectors: a registry (or none), the exact package text, and the expected report or refusal. An implementation conforms if it reproduces every expected outcome. Two implementations do so today: the Scala reference and a JavaScript verifier that shares no code with it (`tooling/evidence-conformance.mjs`).

The older admission vectors under `test-vectors/evidence-statement/v1/` exercise the same rule. They predate this protocol: they record the reference implementation's status name, and an input mismatch as `MALFORMED`.

[`examples/order-transition/`](examples/order-transition/) holds one package and the registry a relying party would supply.

## 11. Relationship to other attestation formats

- **DSSE and in-toto attestations** wrap a typed statement in a signed envelope. A WVP package differs in that it carries the inputs needed to recompute the result, not only a signed result. An issuer-signed decision could be carried in such an envelope; v0.1 does not, to avoid a second canonicalization.
- **IETF SCITT** concerns registering signed statements in a transparency service and proving their inclusion. That addresses when something was recorded and that it was not withheld, which this protocol leaves to the ledger and to future checkpoints.
- **W3C Verifiable Credentials** express claims by an issuer about a subject. A decision could be issued as one; that would say who vouches for it, and would still not make it reproducible.

These are positioning notes, not commitments, and they do not describe those specifications in detail.

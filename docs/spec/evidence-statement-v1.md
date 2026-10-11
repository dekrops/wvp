# Verified Evidence Statement v1

|                      |                                                                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------ |
| Identifier           | `verified-evidence-statement-v1`                                                                       |
| Version              | 1                                                                                                      |
| Status               | Draft                                                                                                  |
| Depends on           | [`verified-json-v1`](../../protocols/canonical-json/v1/SPEC.md)                                        |
| Normative references | RFC 8032 (Ed25519); RFC 8410 (Ed25519 `SubjectPublicKeyInfo`); RFC 4648 (base64); FIPS 180-4 (SHA-256) |
| Conformance          | [`test-vectors/evidence-statement/v1`](../../test-vectors/evidence-statement/v1)                       |

`verified-evidence-statement-v1` is the protocol by which an issuer, such as an Evidence Gateway in front of an ERP, signs what it observed so that any verifier can later establish who asserted it and that it was not altered. The Scala reference is `modules/evidence-protocol`; the language-neutral conformance corpus is `test-vectors/evidence-statement/v1`; an independent JavaScript implementation is `tooling/evidence-conformance.mjs`.

## What a statement is, and is not

A statement is **evidence**: an attributable, tamper-evident assertion that an issuer observed something about a subject. It is not:

- **truth**: a correctly signed statement can be false; the signature proves only who said it;
- **a claim**: a work claim is a separate object naming its evidence (`WorkClaim.evidence`);
- **a verification result**: only a contract's verifier produces a result, from admitted evidence;
- **a ledger record**: admission and verification are recorded on the tenant's ledger separately.

Signature verification produces an `AuthenticatedStatement`. There is no operation from an authenticated statement to a verification result; the only path is admission into an `EvidencePackage` and evaluation by the contract's verifier, which can return `Supported`, `Contradicted` or `InsufficientEvidence` for perfectly authentic evidence. The corpus pins this with `valid/admission-authentic-agent-trace-is-insufficient` and `valid/admission-authentic-contradiction`.

## Wire form

A signed statement is a JSON object with exactly two members, `statement` and `signature`. JSON shapes follow the existing Verified wire conventions (as in Evidence Package v1): UUID references are `{ "value": "<lowercase uuid>" }`, times are `{ "value": "<instant>" }`, hashes are `{ "algorithm": "sha-256", "hex": "<64 lowercase hex>" }` and enumerations are single-key tagged objects such as `{ "StateTransition": {} }`.

`statement` has exactly these members:

| Member       | Meaning                                                                                                                                                                                                    |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `protocol`   | `verified-evidence-statement-v1`. Any other value is refused.                                                                                                                                              |
| `id`         | Evidence ID (UUID). Unique within an evidence set.                                                                                                                                                         |
| `tenant`     | `{ "value": "<tenant id>" }`. The tenant the issuer's key is trusted for.                                                                                                                                  |
| `kind`       | Evidence type: `StateTransition`, `DatabaseChange`, `ApiResponse`, `Event`, `Document`, `AgentTrace`, `SignedAttestation`, `HumanWitness`, `SensorObservation`, `ExternalAssertion`, `CryptographicProof`. |
| `subject`    | `{ system, kind, key }`: the business object the statement is about.                                                                                                                                       |
| `issuer`     | The asserting actor (UUID).                                                                                                                                                                                |
| `source`     | `{ system, observationId }`: the system the issuer observed and its observation identifier.                                                                                                                |
| `observedAt` | Asserted observation time. Not authenticated.                                                                                                                                                              |
| `payload`    | Commitment to the evidence body: SHA-256 of the body's canonical JSON. The body itself travels separately and may be withheld.                                                                             |
| `chain`      | `null`, or `{ stream, sequence, previous }`: the step's position in the issuer's stream. `previous` is `null` exactly at sequence 0.                                                                       |

`signature` has exactly `scheme` (`Ed25519`), `keyId` and `encoded` (standard base64 of the 64-byte signature).

Times use the canonical spelling of an instant: `YYYY-MM-DDTHH:MM:SSZ`, or with a fraction of exactly 3, 6 or 9 digits using the shortest group that represents it (java.time `Instant#toString`). A statement whose re-encoding differs from its received form in any way — an unknown member, a missing member, a number given as a string, a non-canonical time or UUID spelling — is refused as `MALFORMED`. Implementations need not agree on why such input is malformed; they must agree that it is refused.

## Canonical bytes, digest and signature

- **Canonical bytes** of a statement: `verified-json-v1` (see [Canonical JSON](../../protocols/canonical-json/v1/SPEC.md) and ADR 0019).
- **Statement digest**: SHA-256 of the canonical bytes. It identifies the statement in chains and in admission provenance.
- **Signing input**: the UTF-8 domain prefix `verified:evidence-statement:v1\n` followed by the canonical bytes. The prefix is the same domain-separation scheme as the commercial protocol's `verified:<purpose>:v1\n`, so a statement signature can never be valid for another Verified object, and vice versa.
- **Signature**: Ed25519 (RFC 8032) over the signing input, verified strictly by the platform library.

## Verification procedure

Checks run in this order and stop at the first failure, so every implementation reports the same code for the same input:

1. Structure (as above) — `MALFORMED`.
2. `protocol` is `verified-evidence-statement-v1` — `UNSUPPORTED_PROTOCOL`.
3. `payload` and any `chain.previous` are well-formed SHA-256 commitments — `MALFORMED_COMMITMENT`.
4. `signature.keyId` names a key in the verifier's trust registry — `UNKNOWN_KEY`.
5. Key and signature scheme are both `Ed25519` — `UNSUPPORTED_ALGORITHM`.
6. The key is trusted for the statement's `tenant` — `TENANT_MISMATCH`.
7. The key belongs to the statement's `issuer` — `ISSUER_MISMATCH`.
8. The key is authorized for the statement's `source.system` — `SOURCE_NOT_AUTHORIZED`.
9. The key was valid at `observedAt`: `validFrom ≤ observedAt < validUntil` and before any `revokedAt` — `KEY_NOT_VALID`.
10. The signature verifies over the signing input — `SIGNATURE_INVALID`.

The trust registry is verifier configuration (`TrustRegistry`), never data received with the evidence. Each `TrustedKey` binds an opaque `keyId` to an Ed25519 public key (base64 DER SubjectPublicKeyInfo), one issuer, one tenant, the source systems the issuer is authoritative for, and a validity period. A registry holds each key ID and each public key at most once. A key authorized only for an agent's own runtime therefore cannot sign an observation of the ERP, whatever kind the statement claims. See ADR 0020.

## Chains

A chain segment is a list of authenticated statements in received order, optionally with a trusted anchor (a previously verified head). Checks, in order:

1. Every statement has a chain link — `CHAIN_MISSING`.
2. One tenant, one issuer and one stream, also matching the anchor: a stream is identified by all three — `CHAIN_MIXED_STREAMS`.
3. No two different statements with the same sequence number — `CHAIN_EQUIVOCATION`.
4. Received order strictly ascending — `CHAIN_REORDERED`.
5. Without an anchor the segment starts at genesis (sequence 0, no previous); a segment starting mid-stream needs an anchor. With an anchor it continues it — `CHAIN_GENESIS_INVALID`, `CHAIN_GAP`, `CHAIN_PREVIOUS_MISMATCH`.
6. Each step is the next sequence number and names its predecessor's digest — `CHAIN_GAP`, `CHAIN_PREVIOUS_MISMATCH`.

A verified segment establishes that the statements are consecutive steps of one issuer's stream, in order, with nothing inserted, removed or altered between the first and the last. It does not establish anything after the last step: a truncated tail is accepted (`valid/chain-truncated-tail-is-undetectable`). See ADR 0021.

## Admission

Admission turns authenticated statements into the evidence of one claim. Checks, in order:

1. Every statement belongs to the claim's tenant, which admission takes from the caller, never from the statements — `FOREIGN_TENANT_EVIDENCE`.
2. No duplicate evidence IDs among the statements or in the claim — `DUPLICATE_EVIDENCE_ID`.
3. Every statement is named by the claim — `EVIDENCE_NOT_CLAIMED`.
4. Every evidence ID the claim names is supplied — `MISSING_EVIDENCE`.
5. Every body's canonical SHA-256 equals its statement's `payload` — `PAYLOAD_MISMATCH`.

The result carries the tenant together with the package (`AdmittedEvidence`), because the core evidence types are tenant-agnostic; it must only be written to that tenant's ledger and stores. The admitted `Evidence` records the issuer as witness, `WitnessTrust.Signed`, the asserted observation time, the admission time and the statement digest as the input of a `verified-evidence-statement` 1.0.0 transformation. Items are ordered by evidence ID. The resulting package is evaluated by the contract's verifier exactly like any other evidence; admission never sets a verification status.

## Conformance

`test-vectors/evidence-statement/v1` holds `valid/`, `invalid/` (not a well-formed statement) and `must-reject/` (well-formed but unacceptable) vectors of three kinds — `statement`, `chain` and `admission` — plus the deterministic test keys in `keys.json`. Each vector is self-contained: it carries the trust registry, the exact input text and the expected outcome (canonical bytes, digests, chain summary, manifest digest, verification status, or the first error code). See ADR 0023.

## Versioning

Changing any member, encoding rule, check, check order or error code requires a new protocol version and a new vector directory; v1 vectors are never regenerated with different expectations. Unknown versions fail closed. See ADR 0024.

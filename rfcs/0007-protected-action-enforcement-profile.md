# RFC 0007: Protected-action enforcement profile (draft)

| | |
|---|---|
| RFC | 0007 |
| Status | Draft; discussion only |
| Created | 2026-10-18 |
| Affects | New optional enforcement profile; no change to published WVP objects, hashes, signatures, vectors or verdicts |
| Related | RFC 0001, RFC 0002, RFC 0003, RFC 0006; issue #41 |

## Summary

Define an **optional** protected-action enforcement profile for agents and enterprise connectors. A trusted egress boundary serializes protected outbound dispatch starts with applicable revocation barriers, under a replicated linearizable coordinator. The profile distinguishes work verification, relying-party acceptance, authorization admission, actual network dispatch, and target-system outcomes. The initial target is a GitHub App–controlled pull-request merge showcase.

**Conditional guarantee:** for an affected scope, if a revocation barrier has been acknowledged and committed as *enforcement-final*, no new protected HTTP dispatch starts through the conforming trusted egress boundary under revoked authority. Already started requests may complete later. No target-level commit or global revocation guarantee is implied.

A merely committed policy event or a consensus admission entry is **not** evidence of physical dispatch ordering.

## Scope and non-goals

In scope: protected action normalization, authenticated authorization, dispatch ownership, revocation barriers, fencing, durable evidence, replay/idempotency, unknown outcomes, conformance tests, and offline verification of the resulting evidence.

Out of scope: replacing Work Contract Language or its three-valued evaluator; replacing claim-registration v1; making GitHub's merge operation transactional; claiming exactly-once external effects; building a new consensus algorithm; requiring recursive proofs for the initial demo; selecting DSSE/JCS before RFC 0006 concludes.

The broader architecture envisages: independently signed DSSE attestations referring to native Work Record digests; WVP-controlled identity federation; separate relying-party acceptance policies; Cedar/Rego restricted frontends compiled to a small typed IR with explicit relying-party approval; signed policy-activation events; a Merkle event log plus authenticated state map; recursive/incremental proofs of authorized state transitions; and finalized grants with a deny-only pending-restriction overlay. **These are dependent proposals, not established normative WVP features.** Each requires its own reviewable profile/specification and implementation evidence.

## Trust and deployment assumptions

1. Protected writes are mediated exclusively by the trusted egress boundary; agents and generic workers lack GitHub write credentials and bypass network paths.
2. The coordinator offers linearizable operations and survives only the failures promised by its deployment/quorum configuration. On quorum loss, new protected dispatch fails closed.
3. Egress owns the actual network-send boundary, not merely an intent queue. Its active-owner transitions prevent old owners from sending; leader election or a lease token alone is insufficient.
4. GitHub App installation tokens can remain valid after a worker loses ownership. Therefore stale workers must never possess independently usable write tokens or outbound routes.
5. Credential theft, privileged cluster/node compromise, direct administrative writes, or bypass paths are outside the initial guarantee and must be disclosed.
6. The target API is external and cannot be atomically committed with the coordinator. In-flight requests can complete after revocation. Crash uncertainty must be represented.
7. Registry timestamps are assertions under the registry trust model; external authenticated time, freshness and non-equivocation require separate evidence.
8. The cryptographic algorithms, canonical byte encodings, purpose-separated signing inputs and object schemas must be explicitly versioned. Native WVP objects retain their existing bytes and meanings.

## Proposed logical objects (schemas non-normative pending vectors)

- `ActionIntent`: tenant, principal, target, operation, resource, normalized parameters digest, expected target precondition (e.g. PR head SHA), idempotency key, Work Contract reference.
- `DispatchAdmission`: intent digest, applicable finalized policy reference, restrictive-overlay reference, authorization decision, coordination index, scope/epoch, unique reservation.
- `DispatchPermit`: action digest, active egress generation, dispatch owner, scope/epoch, single-use nonce and admission reference; **not** a bearer capability usable outside egress.
- `RevocationBarrier`: affected authorization scope(s), predecessor state/epoch, revocation event commitment, barrier index.
- `BarrierAcknowledgment`: authenticated egress identity/generation, exact barrier digest, fenced scope, last permitted dispatch-start index, proof of enforcement-boundary transition under the deployment model.
- `DispatchRecord`: attempt ID, intent digest, coordinator ordering evidence, egress generation, dispatch-start evidence, result status.
- `ExecutionOutcome`: completed, failed, or unknown; target identifiers and reconciliation evidence.
- `EnforcementCheckpoint`: versioned references to policy root, event-log root, proof verification key/profile and egress barrier position. Future format only.

Each object needs an explicit schema, hash/signature domain, max size, parse/refusal rules, issuer role and version dispatch before publication. Do not use an untrusted DSSE `keyid` as authorization.

## Abstract state machine

For each overlapping authorization scope maintain:
- `finalizedGrants`, identified by a proof-finalized policy checkpoint;
- `pendingRestrictions`, authenticated and admitted, deny-only;
- `epoch` and `barrierState` (OPEN, REQUESTED, FENCED, ENFORCEMENT_FINAL);
- `activeEgressGeneration`;
- unique action reservations, dispatch attempts and outcome states.

Effective permissions = finalized grants intersected with all applicable pending restrictions. Unknown required facts never grant permission.

A revocation request first prevents new admissions. A barrier becomes enforcement-final only after the trusted send boundary proves or attests under its enforced deployment assumptions that stale senders cannot initiate affected dispatches. If fencing cannot be established, **do not report enforcement-final**; affected dispatches remain blocked and the incident remains unresolved.

Authorization, dispatch-start and revocation ordering must share a well-defined conflict domain, including overlapping tenant, organization, repository, principal and operation scopes. Per-repository serialization alone does not cover organization-wide revocations.

A dispatch reservation or intent record is not `DispatchStart`. The latter is a defined, instrumented event at the trusted network-send boundary, and its ordering with the barrier must be implemented—not inferred from the coordinator's earlier permit grant.

## Normative target invariants (to prove/test before advancing Draft)

**E1 — No unmediated protected dispatch.** Every protected outbound write originates at an authenticated, current trusted egress boundary.

**E2 — Revocation ordering.** For any action `a` affected by revocation `r`, if `EnforcementFinal(r) < DispatchStart(a)`, then `DispatchStart(a)` is refused. Both operations are linearized by the defined send-boundary protocol.

**E3 — No stale-owner dispatch.** After egress generation `g+1` is active and old generation `g` has been fenced, `g` cannot initiate protected dispatch. Merely issuing a newer fencing token does not establish E3.

**E4 — Fail closed.** Coordinator quorum loss, unconfirmed fencing, missing policy freshness, conflicting authenticated histories or unknown authority prevent new protected dispatch.

**E5 — Deny-only provisional overlay.** Pending events cannot add permissions; invalid or unauthenticated restrictions do not alter authority.

**E6 — Exact action binding.** Admission and dispatch refer to the same normalized action digest and immutable target preconditions. Changed parameters require new authorization.

**E7 — Idempotency.** Within the defined scope, the same idempotency key cannot reserve two different action digests; duplicate requests do not trigger independent gateway dispatch attempts.

**E8 — Honest uncertainty.** Intent, dispatch-start and target completion are distinct states. Timeouts/crashes cannot be represented as definitive non-execution without evidence. Reconciliation precedes retries when effects may have occurred.

**E9 — Historical immutability.** New revocation, policy, proof or trust evidence yields a new assessment; old Work Records, WVP commitments and signed heads are not rewritten.

**E10 — Reproducible acceptance.** The acceptance result references exact Work Record, approved IR, trust context, assurance facts, applicable policy-state checkpoint and verifier semantics. A DSSE signature establishes neither business correctness nor source completeness.

## Merkle policy state and recursive proof profile (future, separate conformance)

Maintain an append-only event log root and an authenticated map root. A joint checkpoint binds registry, stream, size, log root, map root, transition version, authorization-context commitment, and proof verification-key/profile ID. A proof must link a trusted prior checkpoint, authorized event(s), exact log append and deterministic state transition to the next checkpoint. Merkle membership alone does not prove the state root was correctly derived from the event log.

Recursive proof acceptance is **not** a replacement for coordinator freshness or physical egress fencing. A valid proof proves its encoded relation under stated cryptographic assumptions, not GitHub completion or global non-equivocation.

Keep native claim-registration v1 heads and hashes unchanged. A future migration must explicitly link old and new commitments with verifiable migration evidence and new version dispatch; do not reinterpret old heads or regenerate old vectors.

## DSSE / JCS compatibility

RFC 0006 remains Draft. The enforcement profile does not adopt DSSE or JCS. External DSSE envelopes may carry optional attestation statements with stable IDs defined over exact payload type and bytes (e.g. hash of DSSE PAE), while native Work Record identity remains its existing versioned commitment. Envelope JSON encoding and signature ordering must not redefine statement identity. JCS and native canonicalization decisions remain separate; no fallback parser or signature-mode guessing.

## Security and failure model

Consider stale/partitioned workers, paused senders, credential leakage, coordinator split-brain, quorum loss, replayed permits, overlapping scope revocations, malformed payloads, equivocation, stale heads, compromised signing keys, lost GitHub responses, non-idempotent retries, and direct API bypass. The profile must state the conditions under which E1–E10 hold and downgrade its claims when those conditions are not met.

Do not assert universal immediate revocation, target-level fencing, exactly-once GitHub effects, authenticated time, globally fresh policy state or fully proven deployed implementation.

## Conformance / acceptance gates

1. Deterministic scheduler tests for revoke-before-send, send-before-revoke, revoke-after-admission-before-send, pause/resume, owner failover, quorum loss and overlapping scopes.
2. Simulated network-send boundary that distinguishes dispatch intent from actual start. Tests must fail for a naïve check-then-send implementation.
3. Duplicate idempotency key and conflicting action digest tests; crash before/after send; unknown outcome and reconciliation.
4. Signed event, proof and checkpoint validation; invalid signer/role/tenant/scope, stale epoch, conflicting heads, wrong policy digest, forged barrier acknowledgment.
5. End-to-end GitHub App merge on a disposable protected repository, using exact expected PR head SHA; branch rules, credential isolation and direct bypass attempts documented.
6. Offline independent verification of admission, barrier, dispatch and Work Contract evidence; negative fixtures and stable refusal categories.
7. Explicit threat-model review, observed latency and availability/failure measurements. Never substitute benchmark targets for measured guarantees.

## Process and adoption

This RFC is a **proposal for a study and optional profile**, not a published protocol. RFC 0001 governs acceptance and versioning. Implementation begins as an experimental feature in `verified`; the authoritative protocol/specification and vectors follow the repository's source/export process. Existing claim-registration v1, WVP v0.2, Work Contract Language and Lean evaluator semantics are unaffected. RFC 0006 and #41 remain independent.

## Open questions requiring proof or experiment

- Which concrete trusted send-boundary mechanism makes E2/E3 true across pauses, crashes, partitions and failover?
- What exact overlapping-scope conflict graph and barrier semantics are implementable?
- Which consensus backend and trust boundary are acceptable on EKS?
- Can a stale instance retain GitHub credentials or independent network routes?
- Which GitHub permissions and rulesets constrain bypass in the demo?
- Which policy-root transition and recursive proof system meet measured proving/verification costs?
- What authenticated checkpoint/freshness evidence is required for offline acceptance?

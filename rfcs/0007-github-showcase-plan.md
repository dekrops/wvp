# Implementation plan: GitHub protected-dispatch showcase (RFC 0007 companion)

**Status:** proposed; non-normative. **Goal:** demonstrate a falsifiable gateway dispatch-start revocation guarantee, not GitHub transaction finality. This plan intentionally separates the minimum showcase from the long-term Merkle/recursive-proof architecture.

## Milestone 0 — Freeze guarantee and threat model
**Owner areas:** WVP steward, platform, security.
- Define `DispatchStart` at the instrumented trusted egress send boundary and `EnforcementFinal` at barrier completion.
- Identify GitHub write scope, overlapping revocation scopes, bypass routes, app privileges, deployment trust boundary and exact exclusion of already dispatched requests.
- Review whether the chosen deployment can actually fence a paused/partitioned old sender. If not, **do not claim strict dispatch-start consistency**; reduce guarantee to linearizable admission.
**Gate:** signed-off threat model, precise assumptions and counterexample traces.

## Milestone 1 — Formal state machine and adversarial simulator
**Suggested location:** `verified` Lean model + test harness; WVP experimental documentation.
- Model finalized grants, pending restrictions, coordinator ordering, egress generations, revocation barrier and action lifecycle.
- Prove/validate E2, E3, E4, E5, E7 in the abstract model; include safety and liveness separation.
- Deterministic scheduler controls pause immediately before network send, revocation, crash and ownership transfer.
- Include negative implementation that performs check-then-send: test suite must catch the race.
**Gate:** deterministic counterexamples, model invariants and reproducible CI tests.

## Milestone 2 — Coordinator and trusted egress
**Suggested location:** `verified`; Scala/ZIO control plane and narrow Rust egress candidate.
- Evaluate an established consensus backend; do not implement Raft from scratch. Pin consistency semantics and quorum failure behavior.
- Build durable action normalization, idempotency, admission, barrier, active egress generation and outbox/evidence projections to PostgreSQL. PostgreSQL is not a second authorization authority.
- Enforce credential custody and network path isolation. Gateways/workers never hold GitHub installation tokens.
- Implement a concrete barrier acknowledgment tied to scope, epoch, egress generation and last dispatch-start position. Demonstrate fencing, not just acknowledgment.
- Reject new protected sends on unresolved fencing or quorum loss.
**Gate:** chaos tests for paused sender, old leader, partition, failover and crash; observable zero post-finality dispatch starts.

## Milestone 3 — GitHub App integration
- Dedicated GitHub App on disposable repository; minimum installation permissions, target branch rules and restricted alternative write paths.
- Bind exact repository, PR number, expected head SHA, merge method and idempotency key.
- Test allowed merge; revoke-before-admission; revoke-after-admission-before-send; paused stale worker; duplicate requests; unknown GitHub outcome; attempted direct write bypass.
- Record GitHub outcome independently (PR merged state and merge commit) and avoid blind retries.
**Gate:** end-to-end demo reproduces both successful and denied cases with a documented bypass/administrator boundary.

## Milestone 4 — Evidence, offline verifier and investor demo
- Capture intent, coordinator decision, policy root/epoch, barrier, send-boundary record, target outcome and Work Contract evaluation as separate artifacts.
- Add CLI offline verifier with pinned trust configuration, versioned encodings and explicit UNKNOWN states.
- Provide an investor-facing UI: authorized merge vs revoked merge, with exact event ordering and evidence inspectability.
- Benchmark p50/p95/p99 admission and dispatch overhead, revocation-to-enforcement-final latency, throughput, failover downtime and reconciliation duration.
**Gate:** independent verifier reproduces decision and clearly distinguishes authenticated provenance from business correctness.

## Milestone 5 — Future profile, not a prerequisite for GitHub demo
- Cedar/Rego restricted frontend -> typed Acceptance IR; compile attestation plus relying-party approval of exact IR digest.
- Versioned policy activation event stream; Merkle append-only log and authenticated state map with joint signed checkpoints.
- Recursive/incremental proofs of authorized transitions; independent replay/audit and dispute artifacts.
- RFC 0006 DSSE/JCS comparative fixtures and Witness interoperability (issue #41). No silent changes to legacy commitments.
**Gate:** separate RFCs, explicit proof verification key/semantics, cross-language conformance and benchmarked proof costs.

## Explicit failure/claim matrix

| Scenario | Demo guarantee |
|---|---|
| Revocation enforcement-final before trusted send start | Send denied |
| Request already sent before revocation | May complete later |
| Coordinator unavailable | No new protected dispatch |
| Old owner cannot be demonstrably fenced | Barrier unresolved; protected sends blocked; no false finality |
| GitHub response lost | Outcome UNKNOWN until reconciliation |
| Agent obtains direct write credentials | Outside guarantee; treat as bypass/security failure |
| GitHub admin or other authorized writer merges | Not controlled unless explicitly within protected boundary |

## Repository ownership
- `wvp`: Draft RFC, proposed profile and future conformance vectors via source/export workflow.
- `verified`: Lean model, simulator, coordinator, egress, GitHub adapter, evidence capture.
- `verified-cli`: offline independent verification.
- `verified-studio`: adversarial visualization after core tests work.

**Acceptance criterion:** no claim of G3/strict dispatch-start enforcement without concrete send-boundary fencing evidence and adversarial race tests.

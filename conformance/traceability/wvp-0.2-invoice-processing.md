# Traceability: one verification case, from specification to implementation

Informative. Not part of any specification: nothing here changes a requirement, a vector or an expectation. Where this text and a specification differ, the specification governs.

A worked path through one package for a verification engineer who is new to WVP. It says which definition governs each part of the package, where an implementation checks it, and what the result does and does not establish.

| | |
| --- | --- |
| Protocol | `wvp-0.2` (draft), with `work-contract-1`, `verified-evidence-statement-v1` and `verified-json-v1` |
| Case | [`protocols/wvp/v0.2/examples/invoice-processing`](../../protocols/wvp/v0.2/examples/invoice-processing): `package.json` with the relying party's `registry.json` |
| Same case in the corpus | [`test-vectors/wvp/v0.2/valid/supported.json`](../../test-vectors/wvp/v0.2/valid/supported.json) carries the same package and registry, byte for byte. The environment its statements produce is the one in [`test-vectors/work-contract/v1/cases/01-valid.json`](../../test-vectors/work-contract/v1/cases/01-valid.json): same contract, inputs and completeness statements, and same records (only the fact identifiers differ) |
| This repository at | `bb1cb97` |
| Implementation traced | [`verified-cli`](https://github.com/dekrops/verified-cli) `v0.1.5`, commit `d9e99f5`, the public Rust verifier. The Scala reference and the JavaScript verifier also reproduce the case; they are not public, so nothing below points into them |
| Checked on | 2026-10-22 |

## 1. The case in one paragraph

Tenant `tenant-a` claims (claim `…0501`) that invoice `INV-1001` was processed by the cutoff `1767225600` (2026-01-01T00:00:00Z), under contract `invoice-processing` 1.0.0 (`sha-256:7a85539c…`). The package carries 11 signed evidence statements:

- 5 records from two sources: an invoice, a purchase order, a posting and an approval from `sap-s4`, and the approver's authorization from `identity-directory`;
- 6 completeness statements, one per kind, all `asOf` the cutoff.

The contract has six requirements. All six are `TRUE`, so the decision is `SUPPORTED`. No issuer signed the decision.

## 2. Reproducing it

Each command below was run against `verified-cli` `d9e99f5`, with `E=protocols/wvp/v0.2/examples/invoice-processing`.

| Command | Result |
| --- | --- |
| `verified verify $E/package.json --trust $E/registry.json` | `complete`: integrity, 11 of 11 signatures, signer authority, `SUPPORTED` reproduced, issuer signature `absent`, source truthfulness `NOT established` |
| `verified verify $E/package.json` (no registry) | `incomplete`: integrity only. Nothing about signatures or the decision |
| `… --json` | The report, including the computed work record (`workRecord`) |
| `… --record <that record>` | Accepted |
| `… --record <that record, with contractVersion changed>` | `RECORD_MISMATCH`, which names `contractVersion` |
| `… --expect-tenant tenant-b` | `TENANT_NOT_EXPECTED` |
| `VERIFIED_CONFORMANCE_DIR=<wvp>/test-vectors cargo test -p verified-verifier --test conformance` | 54 package vectors and 7 expectation cases reproduced, decisions included |
| `… cargo test -p verified-contract --test conformance` | 641 language cases reproduced; 1 (`72-scale-not-whole`) not representable in `verified-json-v1`, and reported as such |
| `lake exe contract-reference ../../test-vectors/work-contract/v1/cases` (in `formal/lean`) | Lean's reference evaluator: 82 of 82 cases agree, `01-valid` among them |

## 3. Which definitions govern which part

| Part of the package | Governed by |
| --- | --- |
| The whole text; every digest | [`verified-json-v1`](../../protocols/canonical-json/v1/SPEC.md), section 1 |
| Container, manifest, `packageCommitment`, `packageId` | [`wvp-0.1`, section 2](../../protocols/wvp/v0.1/SPEC.md#2-package), unchanged by `wvp-0.2` |
| `claim.json`, `inputs.json`, `decision.json`, `evidence/bodies.json` | [`wvp-0.2`, section 1](../../protocols/wvp/v0.2/SPEC.md#1-components) and [section 4](../../protocols/wvp/v0.2/SPEC.md#4-decision-object) |
| `contract.json` | [`work-contract-1`](../../protocols/work-contract/v1/SPEC.md), sections 2 to 5; canonical form and digest in [section 9](../../protocols/work-contract/v1/SPEC.md#9-canonical-form-and-digest) |
| `evidence/statements.json` | [Evidence Statement v1](../../docs/spec/evidence-statement-v1.md): wire form, signing input, the ten-step verification procedure, admission |
| From statements to an environment | [`wvp-0.2`, section 2](../../protocols/wvp/v0.2/SPEC.md#2-from-signed-statements-to-an-environment) |
| Evaluation and the decision | [`work-contract-1`, section 7](../../protocols/work-contract/v1/SPEC.md#7-evaluation) |
| Order of checks, refusal codes | [`wvp-0.1`, section 7](../../protocols/wvp/v0.1/SPEC.md#7-verifying-a-package), with the differences in [`wvp-0.2`, section 3](../../protocols/wvp/v0.2/SPEC.md#3-verifying) |
| Relying-party expectations | [`wvp-0.2`, section 3.1](../../protocols/wvp/v0.2/SPEC.md#31-relying-party-expectations) |
| Work record | [`wvp-0.2`, section 7](../../protocols/wvp/v0.2/SPEC.md#7-work-record) |
| What a result establishes | [`wvp-0.1`, section 8](../../protocols/wvp/v0.1/SPEC.md#8-what-verification-establishes); [`work-contract-1`, section 13](../../protocols/work-contract/v1/SPEC.md#13-what-a-decision-establishes) |

## 4. Requirement → implementation, test or proof

Paths under `verified-cli/` are at commit [`d9e99f5`](https://github.com/dekrops/verified-cli/tree/d9e99f54803a1b74f0f0dd53bf1815d2238b8046). "Corpus" means the vectors of this repository, which `verified-cli` reproduces in [`crates/verified-verifier/tests/conformance.rs`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/tests/conformance.rs) and in its CI's `conformance` job.

| # | Requirement | Where `verified-cli` checks it | Test or proof |
| --- | --- | --- | --- |
| 1 | The text is canonical (`wvp-0.1` §7, step 1; `verified-json-v1` §1) | [`container.rs:143`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/container.rs#L143), using [`verified-canonical/src/parse.rs:191`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-canonical/src/parse.rs#L191) | Corpus: `invalid/not-canonical.json`; [`canonical-hash-v1.json`](../../test-vectors/canonical-hash-v1.json). Not modelled in Lean |
| 2 | Versions, members, component set, component digests, commitment (steps 2–6) | [`container.rs:154`–`217`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/container.rs#L154) | Corpus: `must-reject/component-digest.json`, `invalid/v0.1-protocol.json` |
| 3 | Components are well formed; the contract is a well-formed `work-contract-1` contract (step 7, `wvp-0.2` §3) | [`work_contract.rs:202`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L202); readers in [`verified-protocol/src/v02.rs`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-protocol/src/v02.rs) | Corpus: `invalid/contract-ill-formed.json`, `invalid/contract-with-code.json`, `invalid/body-is-two-things.json` |
| — | **Integrity established.** Without a registry, verification stops here | [`work_contract.rs:225`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L225) | Corpus: `valid/integrity-only.json` |
| 4 | The decision names `wvp-0.2` and `work-contract` 1 (step 8) | [`work_contract.rs:229`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L229) | Corpus: `must-reject/other-evaluator.json` |
| 5 | Each statement verifies under the registry: Evidence Statement v1, "Verification procedure", steps 1–10 (step 9) | [`statement.rs:23`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/statement.rs#L23) | Corpus: `must-reject/signer-not-authorized-for-source.json`; [`test-vectors/evidence-statement/v1`](../../test-vectors/evidence-statement/v1). Signatures are not modelled in Lean |
| 6 | Admission: tenant, unique identifiers, exactly the claimed statements, payload digests (step 10) | [`statement.rs:95`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/statement.rs#L95) | Corpus: `must-reject/unclaimed-evidence.json`, `missing-evidence.json`, `record-changed.json` (`PAYLOAD_MISMATCH`). Lean models admission only for the v0.1 evaluator ([`Evidence.lean`](../../formal/lean/Verified/Evidence.lean)) |
| 7 | Input conditions 1–5: tenant, contract digest, order of times, `observedAt ≤ ingestedAt`, `asOf` not after observation (step 11) | [`work_contract.rs:162`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L162), times in [`work_contract.rs:92`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L92) | Corpus: `must-reject/claim-names-another-contract.json`, `claim-of-another-tenant.json`, `completeness-after-statement.json` |
| 8 | Statements become an environment; the source is the statement's `source.system`, never the body's (`wvp-0.2` §2) | [`work_contract.rs:33`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L33) | Corpus: `valid/authentic-but-not-accepted.json`. The example's environment equals language case `01-valid` (section 2) |
| 9 | Evaluation: acceptance, conformance, work bound, conflicts, closed kinds, strong Kleene logic, decision (`work-contract-1` §7) | [`verified-contract/src/evaluate.rs:283`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-contract/src/evaluate.rs#L283); closed kinds at [`:326`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-contract/src/evaluate.rs#L326) | 641 language cases (section 2). **Proved in Lean** for steps 7.7 and 7.8: [`Semantics.lean`](../../formal/lean/Verified/Contract/Semantics.lean) defines them, and [`Theorems.lean`](../../formal/lean/Verified/Contract/Theorems.lean) proves the results section 5 uses. Steps 7.1–7.6 are implemented in Lean's reference evaluator but not proved ([`formal/lean/README.md`](../../formal/lean/README.md#trust-boundary-between-the-three-implementations)) |
| 10 | The reproduced decision equals `decision.json`, commitments included (step 12, `wvp-0.2` §4) | [`work_contract.rs:250`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L250) | Corpus: `must-reject/decision-changed.json`, `requirement-value-changed.json` |
| 11 | Every issuer signature counts, over `verified:wvp-decision:v0.2\n` (step 13) | [`verify.rs:136`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/verify.rs#L136) | Corpus: `valid/issuer-signed.json`, `must-reject/issuer-signature-by-evidence-key.json`. In this case: none carried, so `absent` |
| 12 | Expectations: tenant, contract digest, claim identifier, in that order (`wvp-0.2` §3.1) | [`verify.rs:173`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/verify.rs#L173) | [`expectations.json`](../../test-vectors/wvp/v0.2/expectations.json) (7 cases) |
| 13 | Work record: computed from the package, and compared member by member (`wvp-0.2` §7) | Computed at [`work_contract.rs:109`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/work_contract.rs#L109), compared at [`verify.rs:220`](https://github.com/dekrops/verified-cli/blob/d9e99f54803a1b74f0f0dd53bf1815d2238b8046/crates/verified-verifier/src/verify.rs#L220) | **No vector in this repository.** Tested in `verified-cli` and by the commands in section 2. Writing the record to a ledger (ADR 0035) is the reference implementation's and is not public. When a record is compared is [#13](https://github.com/dekrops/wvp/issues/13) |
| 14 | Source truthfulness | Not checked: no check can establish it | Stated in every report |

## 5. The verdict, requirement by requirement

| Requirement | Form | Value | Needs a closed kind? |
| --- | --- | --- | --- |
| `APPROVAL_RECORDED` | `exists` approval for the invoice | `TRUE` | No: a witness is enough |
| `INVOICE_RECORDED` | `exists` invoice with that number | `TRUE` | No |
| `POSTED` | `exists` posting of the invoice at or before the cutoff | `TRUE` | No |
| `PURCHASE_ORDER_RELEASED` | `exists` invoice whose purchase order is released | `TRUE` | No |
| `PROCESSED` | `exists` posting at or before the cutoff, **with `not exists` a reversal** before the cutoff, and an approval before the posting by an approver authorized before approving | `TRUE` | **Yes: `reversal`**. "No reversal" can only be concluded from a listing declared complete |
| `VARIANCE_WITHIN_TOLERANCE` | **`forall`** invoices of that number, variance ≤ the policy value `tolerance` (5000, i.e. EUR 50.00, policy `ap-variance-tolerance` version 3) | `TRUE` | **Yes: `invoice`** |

Lean proves why the last two need a closed kind: `exists_false_requires_closed` and `forall_true_requires_closed`. It also proves that a witness is enough for the others: `exists_true_has_witness`. And it proves that `SUPPORTED` means every requirement is `TRUE`: `supported_iff_all_true`. All four are in [`Theorems.lean`](../../formal/lean/Verified/Contract/Theorems.lean). Remove the reversal completeness statement and `PROCESSED` becomes `UNKNOWN`, so the decision becomes `UNDETERMINED`, not `CONTRADICTED`: missing evidence never becomes `FALSE`. That is language case `05c-reversals-not-declared-complete`.

## 6. Time, trust roots and completeness, in this case

### Time: everything is asserted, nothing is anchored

| Time in the package | Value | Who asserts it | How it is used |
| --- | --- | --- | --- |
| Each statement's `observedAt` | 2026-10-01T10:00:00Z | The signing issuer. It is signed, so we know **who** said it, but it is "not authenticated" as the time anything happened (Evidence Statement v1, wire form) | The key must be valid at this time (procedure step 9). It must be ≤ `ingestedAt` (input condition 4) |
| Record times: `posting.at`, `approval.at`, `authorization.since` | 2025-12-20, 2025-12-19, 2025-09-18 | The source, inside the signed body | Compared with the cutoff and with each other by the contract |
| Completeness `asOf` | 2026-01-01T00:00:00Z (all six) | The source | Closes the kind because it is not before the cutoff (`work-contract-1` §7, step 6). It must not be after its statement's observation (condition 5) |
| The cutoff | 2026-01-01T00:00:00Z | The claim, which nobody signs in `wvp-0.2` | The "by when" of `POSTED` and `PROCESSED` |
| `submittedAt`, `ingestedAt`, `assembledAt`, `evaluatedAt` | 2026-10-01T10:01–10:07Z | Whoever assembled the package. No issuer signature binds them here | Only their order is checked (condition 3) |

**The verifier reads no clock.** A key is checked at the `observedAt` the statement asserts, not at the time of verification. So the same package and registry give the same result whenever they are verified. The other side of this is that an issuer can backdate a statement to before a key's revocation, and nothing in `wvp-0.2` can tell. RFC 0003 says so ("every time is asserted by whoever signed it"). [#38](https://github.com/dekrops/wvp/issues/38), part 2, proposes that the report say evidence time is asserted.

### Trust roots: what the relying party brings

1. **The registry** (`registry.json`). It's the relying party's own configuration, never taken from the package. Two of its four keys sign this case:
   - `test-sap-s4-gateway-1` (issuer `…0111`), authorized for `sap-s4` and `sap-archive`;
   - `test-identity-directory-1` (issuer `…0112`), authorized for `identity-directory`.

   Both are for `tenant-a` and valid from 2026-01-01. The `wvp-decision` key `test-verifier-2` is in the registry but unused, because nothing was issuer-signed.
2. **The contract, by digest.** The package carries its own contract. That it is the agreement the relying party means is established only by `--expect-contract sha-256:7a85539c…`. Without it, the result is about whatever contract the package carries (RFC 0003, G1). The policy values are inside the contract, with their policy versions, so the digest pins them too: `approverRole` = `invoice-approver` (policy `ap-approval-authority` version 1), and `tolerance`.
3. **Which sources count.** The contract says this, not the registry. A validly signed record from a source the contract does not accept is authentic and ignored (`valid/authentic-but-not-accepted.json`).
4. **The verifier and the specification it implements.** Lean's proofs are about the definition, not about `verified-cli`. What relates the two is agreement on the corpus, which is evidence, not proof ([`formal/lean/README.md`](../../formal/lean/README.md#scope-and-authority)).

### Completeness: the source's word, not a fact

The decision rests on the six completeness statements. `PROCESSED` and `VARIANCE_WITHIN_TOLERANCE` could not be `TRUE` without them. Each says "these are all my records of this kind, as of the cutoff". The verifier checks that they are signed by an accepted source and dated correctly. It cannot check that they are true. Three limits apply to this case:

- **It names no claim or record set** (RFC 0003, G3; Lean README, unresolved semantics 2). A record left out of the package after the source declared its listing complete would go unnoticed, and the kind would still be closed.
- **`asOf` is not related to the record times** (unresolved semantics 3). Here `asOf` equals the cutoff, and the records are dated before it. A record dated after `asOf` in a closed kind would be accepted without comment.
- **Observed nine months after the cutoff.** The statements were observed on 2026-10-01, long after the period they describe. That's allowed: "observed long after" is not bounded (unresolved semantics 4).

A later record can overturn the decision: Lean proves `late_record_in_complete_listing_overturns_support` and `withdrawn_completeness_loses_the_decision` ([`Limits.lean`](../../formal/lean/Verified/Contract/Limits.lean)). What does hold is narrower: if nothing contradicts a completeness statement and the question is unchanged, more evidence does not change `SUPPORTED` (`definite_decision_is_stable`).

## 7. Notes: ambiguities and divergences found while tracing

None of these changes a requirement. Each is checked against [#8](https://github.com/dekrops/wvp/issues/8)–[#16](https://github.com/dekrops/wvp/issues/16), [#21](https://github.com/dekrops/wvp/issues/21), [#30](https://github.com/dekrops/wvp/issues/30) and [#38](https://github.com/dekrops/wvp/issues/38).

**N1. The expectations pin the claim's identifier, not its content.** Section 3.1 checks the claim's `id`. The claim's `inputs` (the invoice and the cutoff) are bound by no signature in `wvp-0.2`, so whoever assembles a package can change them and recompute every digest without any key.

To reproduce:

1. Change this package's cutoff from `1767225600` to `1766300000` (2025-12-21).
2. Recompute the claim digest, `decision.commitments.claim`, the manifest and the commitment.
3. Run `verified verify` with all three expectations and `--require-decision SUPPORTED`.

It still returns `SUPPORTED`, `expectations met (tenant, contract, claim)`, exit 0. Only the work record, which holds the claim's digest, tells the two packages apart: `RECORD_MISMATCH … claim, decisionDigest, packageCommitment`.

This is an instance of RFC 0003's G2 ("whoever assembles a package can write any claim over evidence it holds"). Change 1 of that RFC, a signed claim, closes it in `wvp-0.3`. It is not a new issue. But it means that, in `wvp-0.2`, a relying party that wants a particular cutoff must check it through a work record or the claim it holds, not through `--expect-claim`.

**N2. `observedAt` decides key validity, and it is asserted.** See section 6. Covered by [#38](https://github.com/dekrops/wvp/issues/38), part 2, and RFC 0003's threat model. Nothing new.

**N3. Completeness names no claim or record set.** See section 6. Covered by RFC 0003, G3 and change 3, and by the Lean README's unresolved semantics 2–4. Nothing new.

**N4. Two statements of who implements `wvp-0.2` are out of date (not normative).**
- `wvp-0.2` section 1's "Implementation status" names two verifiers (Scala and JavaScript), while this repository's README also lists `verified-cli`, which reproduces every `wvp-0.2` vector (section 2).
- The trust-boundary table in `formal/lean/README.md` has no Rust column, although `verified-cli` reproduces the language corpus too.

No open issue covers either. Both files are exported (`PROVENANCE.md` lists them), so both are corrected at the source and arrive with the next export, not by a pull request here (`governance/publication.md`).

**N5. Chains play no part in this case.** Every statement has `"chain": null`. [#38](https://github.com/dekrops/wvp/issues/38), part 1, concerns packages whose statements carry chain links. Nothing here exercises it.

**N6. No vector for a work record.** Section 7 defines the record, and its comparison is in `verified-cli`, but no vector in `test-vectors/wvp/v0.2` supplies a record and its expected outcome. [#13](https://github.com/dekrops/wvp/issues/13) asks for the vectors that would tell implementations apart. A record vector for this case (accepted, and refused with the members that differ) would be one of them.

## 8. Suggested follow-up

- **N4:** a non-normative correction of the two implementation lists, made at the source and arriving with the next export.
- **N6:** when #13 is decided, add a record vector built on this package.
- **N1:** no new work. It is an example to cite in the review of RFC 0003's change 1.

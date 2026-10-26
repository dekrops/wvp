# Work Verification Protocol v0.2

|                      |                                                                                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Identifier           | `wvp-0.2`                                                                                                                                                                                                                                                                |
| Version              | 0.2                                                                                                                                                                                                                                                                      |
| Status               | Draft                                                                                                                                                                                                                                                                    |
| Depends on           | [`wvp-0.1`](../v0.1/SPEC.md), for everything this document does not restate; [`work-contract-1`](../../work-contract/v1/SPEC.md); [`verified-evidence-statement-v1`](../../../docs/spec/evidence-statement-v1.md); [`verified-json-v1`](../../canonical-json/v1/SPEC.md) |
| Normative references | As `wvp-0.1`                                                                                                                                                                                                                                                             |
| Conformance          | [`test-vectors/wvp/v0.2`](../../../test-vectors/wvp/v0.2)                                                                                                                                                                                                                |

Status: draft. Identifier: `wvp-0.2`.

Version 0.2 is [version 0.1](../v0.1/SPEC.md) with one change of substance: the contract in a package is written in [Work Contract Language 1](../../work-contract/v1/SPEC.md), so what counts as done is data that any verifier evaluates, not the name of an evaluator each verifier must implement.

Everything this document does not restate is as in v0.1: the package container, canonical form, signed [evidence statements](../../../docs/spec/evidence-statement-v1.md), trust registries, the order of checks, the refusal codes, issuer signatures and what verification does not establish. A v0.1 package is not a v0.2 package and the reverse; each verifier refuses the other's.

Implementation status: two verifiers, Scala (`verified-reference verify`) and JavaScript (`tooling/evidence-conformance.mjs`), agree on the vectors in `test-vectors/wvp/v0.2`, decisions included. A verified package can be recorded in the ledger as a work record and exported with it (section 7). No flow in the product produces v0.2 packages; they are submitted. The data in the vectors and the example is synthetic.

## 1. Components

The six component paths are those of v0.1. Their content:

| Component                  | Content                                                                                                    |
| -------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `claim.json`               | `{ id, tenant, contract, inputs, claimant, evidence, submittedAt }`                                        |
| `contract.json`            | A well-formed Work Contract Language 1 contract.                                                           |
| `decision.json`            | `{ protocol, evaluator, decision, requirements, ignored, conflicts, commitments }`                         |
| `evidence/bodies.json`     | `[ { id, body } … ]`, where a body is `{ "record": { kind, fields } }` or `{ "complete": { kind, asOf } }` |
| `evidence/statements.json` | Signed evidence statements (v1), in ascending order of identifier, aligned with the bodies.                |
| `inputs.json`              | `{ tenant, packageId, ingestedAt, assembledAt, evaluatedAt }`, as in v0.1.                                 |

A **claim** names the contract it was made against by digest (`contract`), supplies the contract's declared inputs (`inputs`: an invoice number, a cutoff), and lists the statements it relies on (`evidence`). In v0.1 nothing tied a claim to the contract in its package; here a package whose claim names another contract is refused.

A **body** is what a statement's `payload` commits to: one record a source reported, or one statement by a source that its records of a kind are complete as of a time.

The manifest's `protocol` is `wvp-0.2`; `packageVersion` remains 2. The decision's `evaluator` is `{ "name": "work-contract", "specification": "1" }`.

## 2. From signed statements to an environment

The contract is evaluated against an environment (language specification, section 6) built from the authenticated statements, in ascending order of statement identifier:

- A statement with a `record` body is a fact: `id` is `e-` followed by the statement identifier; `kind` and `fields` are the body's; **`source` is the statement's `source.system`**.
- A statement with a `complete` body is a completeness statement for the body's `kind`, from the statement's `source.system`, as of `asOf`. If several statements declare the same kind complete from the same source, the latest `asOf` stands.
- The environment's inputs are the claim's `inputs`.

The source is never taken from the body. It is the source the statement names, and a statement verifies only if the registry authorizes its signing key to speak for that source. So two separate questions are answered by two separate parties: the **relying party's registry** says who may speak for a source; the **contract** says which sources count for which kind of record. A validly signed record from a source the contract does not accept is authentic and is ignored.

## 3. Verifying

The checks of v0.1 section 7, in the same order, with these differences:

- **Component shapes.** `contract.json` must be a well-formed contract in its canonical form; anything else is `MALFORMED_COMPONENT`. A body is exactly one of the two forms. In the decision, an unresolved conflict has no `resolvedTo` member.
- **Evaluator.** The decision's `protocol` and `evaluator` must be those above; otherwise `UNSUPPORTED_EVALUATOR`. As in v0.1, this and every check after it need a registry. Without one a verifier establishes integrity only: it reports that the components are well formed and unaltered, and nothing about the evaluator, the signatures or the decision.
- **Admission.** As v0.1: every statement belongs to the evaluation's tenant (`FOREIGN_TENANT_EVIDENCE`), identifiers are unique (`DUPLICATE_EVIDENCE_ID`), the statements are exactly those the claim lists (`EVIDENCE_NOT_CLAIMED`, `MISSING_EVIDENCE`), and each body's digest is its statement's payload (`PAYLOAD_MISMATCH`).
- **Input conditions** (`INPUT_MISMATCH` if any fails):
  1. the claim's tenant is the evaluation's tenant;
  2. the claim's `contract` is the digest of `contract.json`;
  3. `submittedAt` ≤ `evaluatedAt`, and `ingestedAt` ≤ `assembledAt` ≤ `evaluatedAt`;
  4. every statement's `observedAt` ≤ `ingestedAt`;
  5. every completeness statement's `asOf` is a number not later than the second in which its statement was observed: a source cannot vouch for a time after it spoke;
  6. the language's evaluation does not refuse the environment (language specification, section 8).
- **Decision.** The reproduced decision must equal `decision.json` exactly: the decision, the value of every requirement, the ignored records and the conflicts. Otherwise `DECISION_MISMATCH`.
- **Issuer signature.** As v0.1, over `verified:wvp-decision:v0.2\n` followed by the canonical decision. A registry authorizes a key for decisions through the source name `wvp-decision`, which is the same for both protocol versions: a key that may sign v0.1 decisions may sign v0.2 decisions. The signing domains differ, so a signature over one cannot be presented as a signature over the other.

### 3.1 Relying-party expectations

A package verifies against its own claim and contract. That the claim and contract are the ones the relying party means can only be established from outside the package. A verifier may therefore be given expectations, from the relying party's own records, and checks them after every check above has passed, in this order:

1. the evaluation's tenant (`inputs.json`) is the expected tenant, otherwise `TENANT_NOT_EXPECTED`;
2. the digest of `contract.json` is the expected contract digest, otherwise `CONTRACT_NOT_EXPECTED`;
3. the claim's `id` is the expected claim, otherwise `CLAIM_NOT_EXPECTED`.

An expectation that is not given is not checked, and nothing in the package can supply one. A later version of the agreed contract verifies on its own and is refused only by this check.

The contract is the expectation that matters most. Whoever assembles a package chooses the contract in it, and a contract whose requirements hold whatever the evidence, with no evidence at all, is reproduced as `SUPPORTED` like any other. A report therefore shows whether the contract was expected: without an expected contract it says that the decision is about the contract the package carries, not one the relying party named (section 5).

This is a clarification of the report. It changes no check, refusal, decision or vector, and a package verifies exactly as before. What a tool does with a decision about a contract nobody pinned, for example when asked whether a required decision was met, is that tool's policy and outside this version.

## 4. Decision object

```json
{
  "protocol": "wvp-0.2",
  "evaluator": { "name": "work-contract", "specification": "1" },
  "decision": "SUPPORTED",
  "requirements": [{ "id": "POSTED", "value": "TRUE" }],
  "ignored": [],
  "conflicts": [],
  "commitments": { "claim": {}, "contract": {}, "evidence": {}, "inputs": {} }
}
```

`commitments.contract` is the contract digest. `commitments.evidence` is the SHA-256 of the canonical JSON array of the statements' digests, in order. `claim` and `inputs` are the digests of those components.

Through `commitments.contract` a decision is bound to the language version, the vocabulary, the accepted sources, the conflict policy, every policy value with its policy version, the evaluation semantics and the requirements: all of them are in the contract, and the digest covers the contract.

## 5. What a report states

```text
Work Verification Protocol package (wvp-0.2)
package integrity     established
contract              invoice-processing 1.0.0, sha-256:7a85…
evidence signatures   established (11 of 11)
signer authority      established under the supplied registry
decision reproduced   SUPPORTED, matches the package
  APPROVAL_RECORDED             TRUE
  …
issuer signature      absent
contract pinned       NO: the decision is about the contract the package carries
source truthfulness   NOT established: no check can establish it
```

The `contract` line identifies which agreement the decision is about. Whether it is the agreement the relying party has in mind is theirs to check, by digest: with an expected contract (section 3.1) the `contract pinned` line is replaced by the expectations that were met; without one it is present, as above. A reproduced decision says that the signed records from the accepted sources establish the requirements under that contract. It does not say the sources told the truth, that a completeness statement was honest, or that the package contains everything the sources know.

## 6. Evidence evaluated and evidence disclosed

A v0.2 package discloses every record it was evaluated against: bodies are carried in full. Evaluating records that are committed to but not disclosed is not part of this version. The language is explicit enough for it (every requirement is a closed formula over typed fields), and a statement already commits to its body by digest, but nothing here defines a proof that a hidden record satisfies a predicate.

## 7. Work record

A **work record** of a package states, for one verification: `claimId`; the digests `claim`, `contract`, `evidence`, `inputs` and `decisionDigest`; `decision`; `packageCommitment`; `contractId` and `contractVersion`; and `protocol`, `evaluator`, `specification`, `language` and `semantics`.

Every member is a function of the package: `claim`, `contract` and `decisionDigest` are the digests of those components; `evidence` and `inputs` are the decision's commitments; `contractId`, `contractVersion`, `language` and `semantics` are read from the contract; the rest from the decision and the container. A record **is about** a package when every member equals the value computed from it.

To check a record offline, verify the package as in section 3, then compare. A verifier that is given a record reports every member that differs and refuses (`RECORD_MISMATCH`), so a record of another contract version, another decision or another package cannot be passed off with this one.

The reference implementation writes such a record to its ledger only after verifying the package under its own registry (ADR 0035). The record is a decision, not an acceptance.

## 8. Conformance

`test-vectors/wvp/v0.2`: `valid/` (accepted, whatever the decision), `must-reject/` (well-formed, refused) and `invalid/` (not a well-formed package), in the format of v0.1's vectors. `examples/invoice-processing` holds one package and the registry a relying party would supply. Never regenerate published expectations.

# Normative audit, October 2026

Informative. What is normative in this repository today, what depends on material that is not public, and where two implementers may read the text differently. Written on 2026-10-11 from the specifications, the corpus, the README, `PROVENANCE.md` and the publication pipeline, as they were at that date.

It changes nothing. Each finding names the issue or RFC that would resolve it ([open questions](open-questions.md)).

## 1. What is normative, and what is not

| Material                                                     | Standing                                                                |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| The eight specifications ([architecture](architecture.md))   | **Normative**, each for its own identifier. All Draft                   |
| Vectors under `test-vectors/`: their inputs and expectations | **Normative** for the outcomes they state. Never changed once published |
| Worked examples under `protocols/*/examples`                 | Informative. Two of them are also checked as vectors                    |
| `README.md`, `test-vectors/README.md`, `PROVENANCE.md`       | Informative                                                             |
| `rfcs/`, `governance/`, `conformance/`, `CONTRIBUTING.md`    | RFC 0001 binds the process. Everything else here is informative         |
| Any implementation's behaviour                               | **Not normative** (RFC 0001, invariant 6)                               |

Two things are normative in practice without being specified:

- **The format of a vector file.** Each corpus has its own shape (`expected.accept`, `expected.error`, `cases[]`, per-corpus keys). An implementer learns it from the files and from another implementation's test harness. It is described in prose in `test-vectors/README.md`, incompletely.
- **The order of members in a report or reading**, where a vector compares a whole object. The order is stated for work relations and left to the vectors elsewhere.

## 2. Dependencies on material that is not public

**Since this audit, two of its findings were resolved** (2026-10-11): the Lean definition that Work Contract Language 1 defers to is published under [`formal/lean`](../formal/lean/README.md), with its proofs, and this repository checks it in its own CI. The two rows are kept below, struck through, so that the record of what was found stays.

| Finding                                                                                                                                                                                                                                                  | Where                                                                 | Why it matters                                                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| ~~**A normative definition is unpublished.**~~ Resolved: published under `formal/lean`                                                                                                                                                                   | `work-contract-1`                                                     | —                                                                                                                                          |
| ~~**Proof claims cannot be checked.**~~ Resolved: the proofs are published, and `formal/lean/check.sh` audits their axioms                                                                                                                               | `work-contract-1`, section 13                                         | —                                                                                                                                          |
| **The generator of the expectations is not public.** Every vector is produced by the Scala reference, which outsiders cannot read or run                                                                                                                 | The whole corpus                                                      | Expectations are checked by a second implementation, which is the safeguard. But a vector cannot be regenerated or extended by anyone else |
| **Specifications name private paths.** Module names, tool scripts, test suites and architecture decision records of the steward's repository, about 25 distinct names across seven specifications. Links to them are removed on export; the names remain | Every specification except the canonical encoding                     | A reader meets `modules/claim-registration` or "ADR 0038" and cannot follow it. Some carry reasoning the text relies on                    |
| **Status paragraphs describe a product.** "One application flow produces and exports packages", "a registry service that implements it exists", "the commercial trial"                                                                                   | `wvp-0.1`, `wvp-0.2`, `work-unit-1`, `verified-claim-registration-v1` | Informative, but mixed into the head of normative documents. It reads as if the protocol depended on one deployment                        |
| **"The platform library".** Evidence Statement v1 asks for Ed25519 "verified strictly by the platform library"                                                                                                                                           | `verified-evidence-statement-v1`                                      | Which signatures are accepted then depends on whose library. See section 3                                                                 |
| **"JVM string order".** The canonical encoding names its key order as UTF-16 code-unit order and glosses it by one runtime                                                                                                                               | `verified-json-v1`, rule 1                                            | The rule itself is precise. The gloss suggests the runtime is the definition                                                               |

## 3. Where implementers may read the text differently

An independent implementation, [`verified-cli`](https://github.com/dekrops/verified-cli), recorded every place where it had to choose a reading: 43 of them, in its `docs/protocol/compatibility.md`. They are the most reliable inventory there is, because each was found by someone implementing from the published text. They are filed as issues here, grouped by specification, and none is decided by this audit:

| Area                                       | Readings | Examples                                                                                                                                                       |
| ------------------------------------------ | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Canonical encoding and numbers             | 3        | Duplicate keys; integers beyond 2^53, which one implementation cannot represent and refuses                                                                    |
| Package container, checks and expectations | 4        | A stated digest with another algorithm name; a component path that is not a string. The two steward implementations give **different refusal codes** for these |
| Time                                       | 2        | Dates that are not instants; a completeness statement observed before 1970                                                                                     |
| Signatures and encodings                   | 2        | What "strict" Ed25519 verification accepts; lenient base64                                                                                                     |
| Trust registry                             | 1        | Absent versus `null` members; unknown members                                                                                                                  |
| Work records                               | 4        | When a record is compared; a record for `wvp-0.1`                                                                                                              |
| Work-unit identity                         | 3        | Which value types identify a unit; validation of names                                                                                                         |
| Evidence statements outside a package      | 6        | The same statement twice; a negative sequence number; what admission returns                                                                                   |
| Claim registration                         | 18       | Order of checks across three documents; when a dispute's window starts; how the open-claim limit counts                                                        |

Beyond that inventory, this audit found:

- **No requirement language.** No specification uses BCP 14 key words. Requirements are written as plain statements of fact ("a verifier refuses"). That is usually unambiguous and occasionally not: where a sentence describes what the reference does, a reader cannot tell a requirement from a description.
- **First-failure order is normative and only partly tabulated.** The protocol's central interoperability rule is that every verifier reports the same first failure. `wvp-0.1` tabulates its thirteen checks. Other specifications give the order in prose, and the inventory above shows implementations diverging exactly there.
- **Resource limits are unspecified.** One specification bounds work (`WORK_LIMIT`). The others set no limit on sizes, counts or nesting, so whether an oversized input is refused, and with what, is each implementation's choice.
- **Cross-specification objects are specified by reference.** `wvp-0.2` is "v0.1 with one change of substance" and restates little. Correct, and it means no single document defines a `wvp-0.2` package.
- **The location of one specification is an accident.** Evidence Statement v1 is at `docs/spec/`, the others under `protocols/`. Moving it would change a published path, so it has not been moved.

## 4. Weaknesses that are in the formats, not the wording

A claims review of these specifications found gaps that no clarification can close, because the formats themselves allow them. They are design questions, and are listed with their RFCs in [open questions](open-questions.md):

- an unpinned verification can report a supported decision with no key involved;
- a completeness statement names neither a claim nor a set of records;
- key validity is evaluated at a time the signer asserts;
- a package's claim and manifest are unsigned, and its issuer signature is optional.

Each specification already says, in its own limits section, that it does not establish these things. The finding is that a reader can rely on more than is established without noticing.

## 5. What holds

So that the list above is not misread:

- The canonical encoding, the digests and the signing inputs are specified precisely enough that two implementations written by different people agree on every vector.
- Signing inputs are domain-separated for every signed object.
- Trust comes only from the relying party's registry, in every specification.
- Every specification states what its result does not establish.
- Expectations have never been regenerated. Each corpus change since publication added cases.

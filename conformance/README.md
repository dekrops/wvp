# Conformance

How an implementation shows which specifications it implements, and how it says so here.

## What conforming means

An implementation **conforms to a specification** when, for every vector of that specification's corpus, it produces the expectation the vector states: the canonical bytes and digests, the report, decision or reading, or the first refusal code.

- **The whole expectation, not a part of it.** Matching a refusal code where the vector also states a detail the specification defines is not reproducing the vector.
- **Every vector.** An implementation that cannot represent an input says so, case by case, and does not count that case.
- **Expectations are never edited** to make an implementation pass ([RFC 0001](../rfcs/0001-standards-process.md), invariant 1). If a vector looks wrong, that is an issue here.
- **The published corpus, at a named commit.** A result is a statement about one commit of this repository.

Conforming says that an implementation agrees with the corpus. It does not say the implementation is correct on inputs the corpus does not contain, and it is not a security assessment.

## Partial support

The family is layered ([architecture](../governance/architecture.md)), and an implementation may implement any specification without those above it. Within one specification, an implementation may support a capability and not another. It then reports each capability separately:

| Capability            | Meaning                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------ |
| **verify**            | It checks objects of the specification and reproduces every vector's expectation                       |
| **produce**           | It emits objects of the specification that a conforming verifier accepts                               |
| **partial: \<what\>** | It reproduces a named subset of the corpus. The report says which files or cases, and why not the rest |
| **not implemented**   | It does not process the specification at all                                                           |

A report MUST NOT claim a specification as a whole when any vector of its corpus is not reproduced. "All of claim registration except heads" is a partial report, and says so.

## Reporting

An implementation reports by a pull request that adds or updates one file, `conformance/reports/<implementation>.md`, with:

1. **The implementation**: name, where its source is, its license, and whether it is independent or binds another implementation (name which).
2. **The version** of the implementation the report is about: a tag or a commit.
3. **The corpus**: the commit of this repository it was run against.
4. **Per specification**: the capability, the number of vectors reproduced out of the number in the corpus, and every case not reproduced with the reason.
5. **How to reproduce the run**: the command, so that anyone can check the report.
6. **Known divergences**: any input, in the corpus or not, where it knowingly differs from the text or from another implementation. These become issues here.

A report is the implementer's own statement. Maintainers check that it has the six parts and that its claims are of the kinds above. They do not certify it, and merging a report is not an endorsement of the implementation.

A report that is no longer true is corrected or removed by its author, or by a maintainer after asking them.

## What this repository checks itself

Every pull request and `main` are checked in public: the structure of the corpus, that it is what the export wrote, that no published expectation changed, and that the public implementations reproduce it, part by part. [What this repository checks in public](ci.md) says what each check establishes and what it does not, and how to run it. That run is evidence beside an implementer's report, not a replacement for one.

A vector for a new rule can be built and checked with public tooling: [proposing vectors](proposing-vectors.md).

For Work Contract Language 1 there is an oracle: [the Lean reference evaluator as a command](oracle/README.md), which says what the published definition yields for any contract and environment.

## Implementations known today

Reports under `reports/` are the authority once they exist. Until an implementation files one, this table repeats what its own compatibility document says, and names that document.

| Implementation                                                          | Independent                          | Public                  | States its results in                                                                                                       |
| ----------------------------------------------------------------------- | ------------------------------------ | ----------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Scala reference (the steward's)                                         | Yes. It generates the vectors        | No                      | Not public                                                                                                                  |
| JavaScript (the steward's)                                              | Yes                                  | No                      | Not public                                                                                                                  |
| Lean 4 reference evaluator, for Work Contract Language 1                | Yes                                  | Yes, in this repository | [`formal/lean/README.md`](../formal/lean/README.md); run by this repository's CI                                            |
| [`verified-cli`](https://github.com/dekrops/verified-cli) (Rust)        | Yes, written from the published text | Yes                     | [`docs/protocol/compatibility.md`](https://github.com/dekrops/verified-cli/blob/main/docs/protocol/compatibility.md)        |
| [`verified-python`](https://github.com/dekrops/verified-python)         | No: binds `verified-cli`'s crates    | Yes                     | [`docs/protocol-compatibility.md`](https://github.com/dekrops/verified-python/blob/main/docs/protocol-compatibility.md)     |
| [`verified-typescript`](https://github.com/dekrops/verified-typescript) | No: binds `verified-cli`'s crates    | Yes                     | [`docs/protocol-compatibility.md`](https://github.com/dekrops/verified-typescript/blob/main/docs/protocol-compatibility.md) |

No specification here yet has two independent implementations of which one is public **and** a published normative definition, which is what Final requires. [The audit](../governance/normative-audit-2026-10.md) says what each lacks.

# Work Verification Protocol

Specifications and conformance vectors for checking claims about completed work: what a claim is, the contract that defines "done", signed evidence, and the decision a verifier reproduces from them. Everything here is a **draft**.

| Specification                                                    | What it defines                                                                                                                                                                                                        | Vectors                                                                      |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| [`verified-json-v1`](protocols/canonical-json/v1/SPEC.md)        | The canonical JSON encoding every digest and signature is over                                                                                                                                                         | [`test-vectors/canonical-hash-v1.json`](test-vectors/canonical-hash-v1.json) |
| [Evidence Statement v1](docs/spec/evidence-statement-v1.md)      | Signed evidence, the verifier's trust registry, chains, admission                                                                                                                                                      | [`test-vectors/evidence-statement/v1`](test-vectors/evidence-statement/v1)   |
| [WVP v0.1](protocols/wvp/v0.1/SPEC.md)                           | Portable verification packages, thirteen ordered checks, refusal codes                                                                                                                                                 | [`test-vectors/wvp/v0.1`](test-vectors/wvp/v0.1)                             |
| [WVP v0.2](protocols/wvp/v0.2/SPEC.md)                           | Packages whose contract is written in Work Contract Language 1; relying-party expectations                                                                                                                             | [`test-vectors/wvp/v0.2`](test-vectors/wvp/v0.2)                             |
| [Work Contract Language 1](protocols/work-contract/v1/SPEC.md)   | Contracts as typed data, with three-valued evaluation                                                                                                                                                                  | [`test-vectors/work-contract/v1`](test-vectors/work-contract/v1)             |
| [Work-unit identity v1](protocols/work-unit/v1/SPEC.md)          | Which unit of work a claim is about, and its nullifier                                                                                                                                                                 | [`test-vectors/work-unit/v1`](test-vectors/work-unit/v1)                     |
| [Claim registration v1](protocols/claim-registration/v1/SPEC.md) | Registering a claim before evidence is asked for: the agreement both parties sign, the registry's receipts and log, responses, withdrawal and supersession, disputes, an audit of the log, and signed heads of the log | [`test-vectors/claim-registration/v1`](test-vectors/claim-registration/v1)   |
| [Work relation v1](protocols/work-relation/v1/SPEC.md)           | Signed statements by which a ledger or an application relates records of one unit of work, and what a reader may conclude from them offline. Draft                                                                     | [`test-vectors/work-relation/v1`](test-vectors/work-relation/v1)             |

## Conformance

A conforming implementation reproduces the expected outcome of every vector: the canonical bytes and digests, the report or decision, or the first refusal code. Expected outcomes are never edited to make an implementation pass. A change of outcome is a new protocol version, in a new directory.

Independent implementations that reproduce these vectors:

- **Scala**, the reference implementation, which generated the vectors published up to 2026-11-17 (not public);
- **JavaScript**, written separately from the Scala (not public);
- **Lean 4**, in [`formal/lean`](formal/lean/README.md): the definition of evaluation that Work Contract Language 1 defers to, with its proofs and a reference evaluator, and models of the v0.1 evaluator, evidence admission, statement chains and the claim registry's states;
- **Rust**, [`verified-cli`](https://github.com/dekrops/verified-cli), written from these specifications. Of claim registration it checks registrations, log segments, audits and units; it does not yet check heads.

Work relation v1 is reproduced by the Scala reference and by Rust (the `verified-history` crate of `verified-cli`, a library without a command), and not by JavaScript.

## What verification establishes, and what it cannot

Under a trust registry the relying party supplies, a package establishes its integrity, who signed each piece of evidence, that each signer was authorized for its source, and that the contract yields the stated decision from that evidence. It never establishes that a source told the truth. A reproduced `CONTRADICTED` or `UNDETERMINED` is a successful verification of a claim that is not supported.

## Data

All vectors and examples are synthetic. Names such as `u.lindqvist` are invented, and the keys are test keys derived from seeds published beside them: never trust or provision them.

## How the protocol changes

The protocol is changed in the open, by RFC: [RFC 0001](rfcs/0001-standards-process.md) defines the process, who decides, and what a change must come with. [`governance/`](governance/) holds the list of maintainers, a map of the specifications and what each depends on, an audit of what is normative here and what still depends on unpublished material, and how this repository is published. [`CONTRIBUTING.md`](CONTRIBUTING.md) says how to raise a question or propose a change, and [`conformance/`](conformance/) how an implementation reports what it reproduces.

WVP is stewarded by Krops GmbH. It is not a standard of any standards body, and nothing here claims that it is.

## Provenance and maintenance

This repository is the source of the protocol. Everything in it is written here, by pull request: specifications, vectors and examples, the Lean definitions, RFCs, governance documents, conformance reports, the contribution guide and this README. How a change is proposed, reviewed and decided has not changed: [RFC 0001](rfcs/0001-standards-process.md), whose invariants still hold. A published expectation is never edited, and a change of outcome is a new version.

Until 2026-11-17, the specifications, vectors, examples, Lean definitions and this README were exported here from the steward's platform repository, where the reference implementation generated the vectors. That export has stopped, and nothing is exported here any more. [`PROVENANCE.md`](PROVENANCE.md) is kept as the record of the last export: its source commit and the SHA-256 of every file it wrote. Changes made since are in this repository's history. [`governance/publication.md`](governance/publication.md) describes the arrangement as it was.

## License

Specifications and other prose (every Markdown file) are licensed under [CC BY 4.0](LICENSE-CC-BY-4.0.txt). Conformance vectors, examples and every other file are licensed under the [Apache License 2.0](LICENSE-APACHE-2.0.txt). See [`LICENSE`](LICENSE).

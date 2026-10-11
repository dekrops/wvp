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

- **Scala**, the reference implementation, which also generates the vectors (not public);
- **JavaScript**, written separately from the Scala (not public);
- **Lean 4**, a reference evaluator for Work Contract Language 1, and a model of the claim registry's states (not public);
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

This repository has two kinds of content, and each has one place where it is written:

- **Specifications, vectors and examples**, with this README and the license files, are exported from the platform repository where the reference implementation generates the vectors, by a script that copies them byte for byte and removes links to files that are not published. [`PROVENANCE.md`](PROVENANCE.md) names the source commit and the SHA-256 of every exported file. A pull request here that edits one of them is not merged as it is: the change is made at the source, by an accepted RFC where the process requires one, and arrives with the next export.
- **RFCs, governance documents, conformance reports and the contribution guide** (`rfcs/`, `governance/`, `conformance/`, `CONTRIBUTING.md`) are written here, by pull request. The export never writes, replaces or removes them.

[`governance/publication.md`](governance/publication.md) describes this arrangement, why it is the first step and not the last, and what has to be true before the specifications themselves are written here.

## License

Specifications and other prose (every Markdown file) are licensed under [CC BY 4.0](LICENSE-CC-BY-4.0.txt). Conformance vectors, examples and every other file are licensed under the [Apache License 2.0](LICENSE-APACHE-2.0.txt). See [`LICENSE`](LICENSE).

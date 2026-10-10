# Work Verification Protocol

Specifications and conformance vectors for checking claims about completed work: what a claim is, the contract that defines "done", signed evidence, and the decision a verifier reproduces from them. Everything here is a **draft**.

| Specification                                                    | What it defines                                                                                                                                                                     | Vectors                                                                      |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| [`verified-json-v1`](test-vectors/README.md)                     | The canonical JSON encoding every digest and signature is over                                                                                                                      | [`test-vectors/canonical-hash-v1.json`](test-vectors/canonical-hash-v1.json) |
| [Evidence Statement v1](docs/spec/evidence-statement-v1.md)      | Signed evidence, the verifier's trust registry, chains, admission                                                                                                                   | [`test-vectors/evidence-statement/v1`](test-vectors/evidence-statement/v1)   |
| [WVP v0.1](protocols/wvp/v0.1/SPEC.md)                           | Portable verification packages, thirteen ordered checks, refusal codes                                                                                                              | [`test-vectors/wvp/v0.1`](test-vectors/wvp/v0.1)                             |
| [WVP v0.2](protocols/wvp/v0.2/SPEC.md)                           | Packages whose contract is written in Work Contract Language 1; relying-party expectations                                                                                          | [`test-vectors/wvp/v0.2`](test-vectors/wvp/v0.2)                             |
| [Work Contract Language 1](protocols/work-contract/v1/SPEC.md)   | Contracts as typed data, with three-valued evaluation                                                                                                                               | [`test-vectors/work-contract/v1`](test-vectors/work-contract/v1)             |
| [Work-unit identity v1](protocols/work-unit/v1/SPEC.md)          | Which unit of work a claim is about, and its nullifier                                                                                                                              | [`test-vectors/work-unit/v1`](test-vectors/work-unit/v1)                     |
| [Claim registration v1](protocols/claim-registration/v1/SPEC.md) | Registering a claim before evidence is asked for: the agreement both parties sign, the registry's receipts and log, responses, withdrawal and supersession, and an audit of the log | [`test-vectors/claim-registration/v1`](test-vectors/claim-registration/v1)   |

## Conformance

A conforming implementation reproduces the expected outcome of every vector: the canonical bytes and digests, the report or decision, or the first refusal code. Expected outcomes are never edited to make an implementation pass. A change of outcome is a new protocol version, in a new directory.

Independent implementations that reproduce these vectors:

- **Scala**, the reference implementation, which also generates the vectors (not public);
- **JavaScript**, written separately from the Scala (not public);
- **Lean 4**, a reference evaluator for Work Contract Language 1, and a model of the claim registry's states (not public);
- **Rust**, [`verified-cli`](https://github.com/dekrops/verified-cli), written from these specifications. It does not yet implement claim registration.

## What verification establishes, and what it cannot

Under a trust registry the relying party supplies, a package establishes its integrity, who signed each piece of evidence, that each signer was authorized for its source, and that the contract yields the stated decision from that evidence. It never establishes that a source told the truth. A reproduced `CONTRADICTED` or `UNDETERMINED` is a successful verification of a claim that is not supported.

## Data

All vectors and examples are synthetic. Names such as `u.lindqvist` are invented, and the keys are test keys derived from seeds published beside them: never trust or provision them.

## Provenance and maintenance

These files are exported from the platform repository where the reference implementation generates them, by a script that copies them byte for byte and removes links to files that are not published. This README and the license files are part of that export too, so the whole repository is replaced at each publication. [`PROVENANCE.md`](PROVENANCE.md) names the source commit and lists every file with its digest. Specifications refer to modules and ADRs of that implementation by name; those are not published.

## License

Specifications and other prose (every Markdown file) are licensed under [CC BY 4.0](LICENSE-CC-BY-4.0.txt). Conformance vectors, examples and every other file are licensed under the [Apache License 2.0](LICENSE-APACHE-2.0.txt). See [`LICENSE`](LICENSE).

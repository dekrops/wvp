# What this repository checks in public

Informative. The [`Conformance`](../.github/workflows/conformance.yml) workflow runs on every pull request and on `main`. It uses only what is public: this repository, [`verified-cli`](https://github.com/dekrops/verified-cli) at a pinned commit, and the Lean toolchain. It does not use the implementation that generates the expectations, which is not public.

## The checks

| Job            | What it establishes                                                                                                                                                                                                                              | What it does not                                                                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Structure**  | Every file of the corpus is well-formed JSON without duplicate members, belongs to a part named in [`corpus.json`](corpus.json), and states an expectation. A stated SHA-256 of canonical text is the SHA-256 of that text                       | That an expectation is right. The format of the vector files is not specified ([open questions](../governance/open-questions.md), C4); the map is tooling |
| **Provenance** | Every exported file is byte for byte the file `PROVENANCE.md` records, and every file outside the paths written here is recorded                                                                                                                 | That the export was faithful to its source, which is not public. A pull request that edits a specification or a vector fails here, as the process intends |
| **Unchanged**  | Between the earlier revision and this one, no published file of the corpus was removed, no file holding one case changed by a byte, and a file holding many cases only gained cases ([RFC 0001](../rfcs/0001-standards-process.md), invariant 1) | Anything about prose. It compares with one earlier revision, so it relies on having run on every change before it                                         |
| **Rust**       | `verified-cli`, written from the published text and sharing no code with the generator, reproduces each part it implements, and ran exactly as many cases as this revision holds                                                                 | Correctness on inputs the corpus does not contain. The count is the one the implementation prints                                                         |
| **Lean**       | The definitions build, every theorem's axioms are audited, and the reference evaluator reproduces every case of Work Contract Language 1                                                                                                         | Independence of authorship: the evaluator and the generator have one author. The evaluator around the proved core is tested, not proved                   |
| **Report**     | A table of every part: how many cases it holds, and what each implementation reported for it                                                                                                                                                     | —                                                                                                                                                         |

The earlier revision's own tool and map judge a change where that revision has them, so a pull request cannot loosen the check that judges it.

## Three outcomes that are kept apart

- **Reproduced.** The implementation ran every case of the part and reported agreement. Where it compares less than the whole expectation, or cannot represent an input, the report says partial and why.
- **Failed.** The implementation disagreed, did not run, or ran fewer cases than the revision holds. The report shows the end of its output, where it names the case and the two outcomes. The expectation is never edited; either the implementation at its pinned commit is wrong, or the change is.
- **Not implemented.** No public implementation is run against the part. This is a gap in coverage and fails nothing.

## Coverage today

Of 976 cases in 18 parts, at this corpus and `verified-cli` `v0.1.4`:

- **937** are in parts a public implementation reproduces.
- **642** of those, Work Contract Language 1, are reproduced by two: Rust reproduces 641, and Lean all 642.
- **39**, the signed heads of claim registration, are reproduced by no public implementation.
- For **3** accepted admissions of evidence, Rust does not compare two members that state one platform's verification result.
- The worked examples under `protocols/` are not part of this report. `verified-cli` verifies two of them in its own tests.

So agreement between an implementation and vectors it generated is nowhere the evidence here. What remains is that one party wrote every expectation: a second public implementation by other authors is what [Final](../rfcs/0001-standards-process.md) requires, and no part has one.

## Running it yourself

```sh
python3 conformance/tools/conformance.py structure
python3 conformance/tools/conformance.py provenance
python3 conformance/tools/conformance.py unchanged --old <a checkout of an earlier revision>

git clone https://github.com/dekrops/verified-cli && git -C verified-cli checkout <the commit in corpus.json>
python3 conformance/tools/conformance.py run --implementation rust --source verified-cli --out results/rust.json
bash formal/lean/check.sh
python3 conformance/tools/conformance.py run --implementation lean --source formal/lean --out results/lean.json
python3 conformance/tools/conformance.py report --results results
```

`conformance.py try` runs proposed vectors through an implementation, one case at a time: see [proposing vectors](proposing-vectors.md).

Python 3.11 or later and nothing else for the first three. Rust and Lean install the toolchains their sources pin.

## Changing what is run

- **A new part of the corpus** arrives with an entry in `corpus.json` in the same change, or the structure check fails. Until an implementation is run against it, the report shows it as not implemented.
- **A newer `verified-cli`**: change its `tag` and `commit` in `corpus.json`, and any check whose command or output changed. One pull request, nothing else in it.
- **Another public implementation**: add it under `implementations`, add one check for each part it reproduces, and a job that builds it at a pinned commit. A check is a command that exits with zero only if every case agreed and prints how many it ran.

## Untrusted pull requests

The workflow runs code from a pull request (the tool, the Lean sources) and code named by it (the pinned commit of `verified-cli`). It therefore runs with a read-only token, no secrets, no credentials left in any checkout, and the `pull_request` event, which gives a fork nothing more. Actions are pinned to commits, and the Lean installer to a checksum.

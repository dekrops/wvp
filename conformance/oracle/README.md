# The oracle: the Lean reference evaluator as a command

Informative. A command-line interface to the reference evaluator of [Work Contract Language 1](../../protocols/work-contract/v1/SPEC.md) that is published in [`formal/lean`](../../formal/lean/README.md). Give it a contract and an environment; it says what the Lean evaluator yields. An implementation in any language can compare its own result with that.

It adds no semantics and changes no published file. Every result is the published function `Verified.Contract.Reference.run`; this package only reads cases and writes results.

## Build and run

Install Lean with [elan](https://github.com/leanprover/elan). The toolchain is the one `formal/lean` pins, and there is no other dependency.

```sh
cd conformance/oracle
lake build
.lake/build/bin/wvp-oracle evaluate ../../test-vectors/work-contract/v1/cases/01-valid.json   # a published case
.lake/build/bin/wvp-oracle evaluate examples/no-completeness.json                             # a case written for this README
.lake/build/bin/wvp-oracle evaluate < cases.jsonl                                             # many, one per line
bash check.sh                                                                                 # everything below, checked
```

## Input

The format of the published corpus, and nothing new. A case file is a JSON object that is either

- **one case:** `{ "contract": …, "environment": … }`, or
- **a batch:** `{ "contract": …, "cases": [ { "environment": … }, … ] }`.

`expected` may be given beside an `environment`; the oracle then also says whether its result is that value. Any other member (`description`) is ignored.

`evaluate` takes case files and directories of them (every `.json` file, in order of name). With no path it reads standard input, one case file's JSON per line, so that a caller can evaluate any number of cases in one process.

## Output

One line of JSON on standard output for each case, in the order of the input. Members are in alphabetical order and there is no insignificant whitespace, so equal results are equal bytes.

| Member    | Value                                                                                                                                           |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `case`    | The path as given, with `#` and the index for a case of a batch; `stdin:` and the line number for standard input                                |
| `outcome` | `result` or `input-error`                                                                                                                       |
| `result`  | For `result`: exactly what a vector's `expected` holds. A decision with `requirements`, `ignored` and `conflicts`, or `{ "refused": "<CODE>" }` |
| `agrees`  | Only where the case stated `expected`: whether `result` equals it                                                                               |
| `error`   | For `input-error`: why the case could not be read                                                                                               |

A summary goes to standard error. `wvp-oracle version` prints the interface version, the language and semantics, and the Lean version.

## Three kinds of failure, kept apart

| What happened                                                                                         | How it is reported                                    | Exit |
| ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ---: |
| Every case has a result, and each agrees with its `expected` where it has one                         | `outcome: result`                                     |    0 |
| **The language refused the case** (a malformed contract, a nonconforming environment, the work limit) | `outcome: result` with `refused`. This is a result    |    0 |
| A result differs from the `expected` the case stated                                                  | `agrees: false`                                       |    1 |
| **The input is not a case:** not JSON, or no `contract` or `environment` member                       | `outcome: input-error`; the other cases are evaluated |    2 |
| **The command could not run:** an unreadable path, no command, no case at all                         | A message on standard error                           |    3 |

Any other exit code is a failure of the tool itself.

## What a result rests on

A result is what one program computes. Part of that program is a definition with proofs, and part is tested only. For the layers of the language:

| Layer (specification section)                                  | In the oracle                                 | Assurance                                                                                           |
| -------------------------------------------------------------- | --------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Reading JSON into a contract and an environment (2 to 6)       | `Reference.contract`, `Reference.environment` | Tested on the corpus. Not proved                                                                    |
| Static rules, typing among them (5)                            | `Reference.wellFormed`                        | Tested. The typing judgement is defined and proved safe; that this checker implies it is not proved |
| Acceptance by source, conformance, the work limit (7.1 to 7.4) | `Reference.evaluateDoc`                       | Tested. Not proved                                                                                  |
| Conflicts and closed kinds (7.5, 7.6)                          | `Reference.evaluateDoc`                       | Tested. Not proved                                                                                  |
| **Truth values, quantifiers, the decision (7.7, 7.8)**         | `Pred.eval`, `decide` in `Semantics.lean`     | **The normative definition.** Its properties are proved                                             |
| Lowering n-ary `and` and `or` to the definition's binary ones  | `Reference.lower`                             | Tested. Not proved                                                                                  |
| Writing the result                                             | `Outcome.json`, this package                  | Tested                                                                                              |

So the oracle is authoritative for the evaluation of a settled environment, because that part is the definition the specification defers to. For everything around it, it is a second implementation: agreement with it is evidence, and a disagreement has to be decided from the specification, not from the oracle.

It reproduces all 642 published cases. It does not compute canonical bytes or digests, does not check that its input is canonical text, and knows nothing of packages, signatures or registries.

## Stability

The interface (arguments, members, exit codes) is version 1, printed by `version`. A result is reproducible for a commit of this repository: the evaluator, the Lean toolchain and this package are all fixed by it.

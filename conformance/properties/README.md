# Property tests and generated cases

Informative. Small, well-typed contracts and environments of [Work Contract Language 1](../../protocols/work-contract/v1/SPEC.md), generated from a model in Lean, and used in two ways: to test properties of the reference evaluator, and to compare it with an implementation written by someone else.

Nothing here is a proof, and nothing here is a conformance vector.

```sh
bash conformance/properties/check.sh                                   # the properties
bash conformance/properties/differential.sh <a checkout of verified-cli>   # Lean against Rust
```

Lean with the toolchain `formal/lean` pins, and [Plausible](https://github.com/leanprover-community/plausible) at the commit of its tag for that toolchain. Plausible is a dependency of this package only; the published definitions still have none.

## What is generated

`Generated.lean`. Every contract has one vocabulary, so that it is well typed by construction: two kinds, each with a text key, an optional integer and an optional boolean. What varies:

- **requirements:** one to three, each a quantifier over a kind, with comparisons against literals and between two records, `and`, `or`, `not`, and one nested quantifier;
- **the contract:** one or two accepted sources, and either conflict policy;
- **the environment:** up to five facts, from accepted sources, from a source no contract accepts and of a kind no contract declares, with fields present or absent and keys that collide or not; and completeness statements, from accepted and unaccepted sources.

Each case can be written in the wire format and read as terms of the semantic definition (`Pred`, `Env`), which is what lets a property compare the two.

**Not generated,** and so not tested here: text ordering, time, decimal and money types, claim inputs, policy parameters, the cutoff, more than two kinds, more than five facts, the work limit, and every malformed input.

## Properties

`Properties.lean`, run with seed 20261012 on 2000 cases each. A property that passes was **not refuted on those cases**. One that fails comes with a counterexample Plausible has shrunk.

| Property                                                                                                                  | Precondition                                | Result      |
| ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------- | ----------- |
| A generated case is evaluated, or refused as `CONTRACT_ILL_FORMED` and nothing else                                       | —                                           | Not refuted |
| The decision is the definition's aggregation of the requirements' values                                                  | The case is evaluated                       | Not refuted |
| **The evaluator's values are those of `Pred.eval`** on an environment built from the specification, without the evaluator | No two accepted facts of a kind share a key | Not refuted |
| A fact from a source the contract does not accept changes no value                                                        | —                                           | Not refuted |
| A fact of a kind the contract does not declare changes no value                                                           | —                                           | Not refuted |
| The order of the facts changes no value                                                                                   | —                                           | Not refuted |
| A fact given twice changes no value                                                                                       | —                                           | Not refuted |
| A completeness statement from an unaccepted source changes no value                                                       | —                                           | Not refuted |
| One more accepted record leaves every definite value as it was                                                            | Its key is new, and its kind is not closed  | Not refuted |

The same statements with a precondition removed are run too, and are **expected to fail**. Each failure is the evidence that the precondition is needed, with a minimal case:

| Without the precondition            | Minimal counterexample found                                                                                                                    |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| "its kind is not closed"            | No facts; kind `b` declared complete. `forall x in b: x.f = true` is `TRUE`. Add one record of `b` whose `f` is false: it is `FALSE`            |
| "its key is new"                    | A record with a key already present and other fields is a conflict; under either policy the kind's records change, and a definite value is lost |
| "no two accepted facts share a key" | The environment built here does not settle conflicts, so it differs from the evaluator's as soon as two facts collide                           |

The run also prints how often each precondition held, so that a pass is not vacuous: of 2000 generated cases, 1979 are evaluated, 1708 have distinct keys, 781 have a definite requirement, 138 are `SUPPORTED` and 470 `CONTRADICTED`.

### What was learned

- **Static rule 8 is reachable by accident.** 21 of 2000 generated contracts were refused because a conjunction held a predicate and its negation. A generator, or an author, who builds predicates mechanically meets this rule; it is correct and worth knowing.
- **The stability theorem's hypotheses are tight.** `definite_decision_is_stable` is proved about the definition for extensions that add no record to a closed kind and remove none. The two failing properties show, on the evaluator, that dropping either part breaks it, in the smallest cases there are. No property was refuted that the specification says should hold.

## Differential testing

`differential.sh` is the pipeline

```text
Lean model → generated cases → Lean reference result → verified-cli's own harness → comparison
```

`wvp-generate <seed> <contracts> <environments> <directory>` writes batches in the format of the corpus's differential cases, each expectation being what `Reference.run` yields, and a manifest with the seed, the generator's version and the Lean version. The implementation must reproduce the whole expectation of every case: the decision, each requirement's value, the ignored facts and the conflicts.

| Run                                  | Generated cases | Reproduced by `verified-cli` `v0.1.4` |
| ------------------------------------ | --------------: | ------------------------------------: |
| Seed 20261012, 250 contracts (in CI) |            2000 |                                  2000 |
| Seeds 1 to 5, 1000 contracts each    |          50 000 |                                50 000 |

No disagreement was found. That is evidence about the fragment that is generated, between two implementations by different authors. It says nothing about what is not generated, and it is not a proof about either.

## Generated cases and vectors

Generated cases are written to `generated/`, which is not committed, and never to `test-vectors/`. Their expectations are one implementation's results. A generated case may become a vector only as [proposing vectors](../proposing-vectors.md) and [RFC 0001](../../rfcs/0001-standards-process.md) say: reviewed, reproduced by implementations that share no code, and carried in by the change it belongs to.

The output is a function of the seed, the two counts, `generatorVersion` in `Generate.lean` and the Lean toolchain. Change what is generated, and change that version.

## Why Plausible

It matches the pinned Lean at a tagged commit, has no dependencies of its own, and gives generators, seeded runs and shrinking, which a hand-written generator would have to rebuild. Its cost is one dependency in a package that is not the normative one. Properties are written as plain Boolean functions, so replacing it would change `check` and the instances, not the properties.

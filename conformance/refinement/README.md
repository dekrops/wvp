# Refinement: from the evaluator to the definition

Informative. An assessment of how the executable evaluator of Work Contract Language 1 can be shown to compute what the semantic definition says, the first results in that direction, and what stands in the way of the rest.

```sh
bash conformance/refinement/check.sh
```

A Lake package beside the published definitions, with no dependency but them. It changes no published file.

## The chain to establish

```text
JSON text ─read─▶ Doc, RawEnv ─check─▶ well-formed ─settle─▶ Env ─lower─▶ Pred ─eval─▶ values ─decide─▶ decision
   (1)                 (2)                  (3)            (4)          (5)              (6)
```

| Step | What it is (specification)                                             | In Lean                             | Status before this package                                                           | Now                                                                                                             |
| ---- | ---------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| 1    | Reading JSON into a contract and an environment (2 to 4, 6)            | `Reference.contract`, `environment` | Tested                                                                               | Tested                                                                                                          |
| 2    | Static rules (5)                                                       | `Reference.wellFormed`              | Tested. The judgement `WellTyped` is proved safe; the checker is not connected to it | Unchanged                                                                                                       |
| 3    | Acceptance, conformance, work bound, conflicts, closed kinds (7.1–7.6) | inside `Reference.evaluateDoc`      | Tested                                                                               | Tested; property tested against the specification where no keys collide ([properties](../properties/README.md)) |
| 4    | `and` and `or` over lists become binary                                | `Reference.lower`                   | Tested. `partial`: no theorem can mention it                                         | **Proved for a total definition of the same function; tested equal to `lower` on every published contract**     |
| 5    | Truth values and quantifiers (7.7)                                     | `Pred.eval`                         | **The definition**, with proofs                                                      | The definition                                                                                                  |
| 6    | The decision (7.8)                                                     | `decide`, `evaluate`                | The definition, with proofs                                                          | **Proved that the evaluator's decision is `evaluate` of its lowered requirements in the environment it built**  |

## What is proved here

Fifteen theorems, standard axioms only, audited by `check.sh`. The ones that matter:

| Theorem                     | Statement                                                                                                                                                                                                          | About                              |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------- |
| `lowerTotal_eval`           | For every predicate in wire form, environment and scope, the lowered predicate's value under `Pred.eval` is the wire form's value, where `and` and `or` are the conjunction and disjunction of all their arguments | A total lowering, defined here     |
| `lowered_decision`          | So the decision over lowered requirements is the decision over their wire forms                                                                                                                                    | The same                           |
| `evaluateDoc_decision`      | Whenever the evaluator returns an outcome, its decision is `decide` of its requirement values                                                                                                                      | **`Reference.evaluateDoc` itself** |
| `evaluateDoc_values`        | There is one environment in which each requirement's value is `Pred.eval` of its lowered predicate                                                                                                                 | **`Reference.evaluateDoc` itself** |
| `evaluateDoc_is_definition` | So its decision is `evaluate`, in that environment, of the lowered requirements                                                                                                                                    | **`Reference.evaluateDoc` itself** |

The last three are proved by unfolding the published function. They are the first theorems about the program the oracle runs, as opposed to the definition it calls.

**What they do not say.** The environment is under an existential: the theorems say evaluation is the definition applied to _an_ environment, and nothing about whether it is the right one. And they mention `lower`, about which nothing is provable. So the unproved part of a decision is now exactly two things: step 3, and that `lower` is `lowerTotal`.

`wvp-lowering` tests the second on every requirement of every published contract: 427 requirements of 78 contracts, no difference.

## What stands in the way

1. **Seven `partial` definitions in the evaluator**: `lower`, `pred`, `nodes`, `depth`, `same`, `typed`, `contradictory`. Lean compiles a `partial` definition to an opaque constant. Each recurses through a list inside the type it recurses on, which is why they were written `partial`; each can be written by structural recursion with a mutual helper over the list, as `lowerTotal` and `lowerList` are here. **Replacing `lower` by that definition, at the source, turns the test above into a theorem and connects `lowerTotal_eval` to the evaluator.** It changes no result.
2. **Step 3 has no specification-level model.** To state that the evaluator's environment is right, "the environment the specification describes" has to exist as a definition: acceptance, conformance, grouping by key, settling a conflict under each policy, closing a kind. That is an intermediate representation between `RawEnv` and `Env`, about 100 lines, and it is the main piece of work. The property test already has a version of it for the case without conflicts (`Case.settled`).
3. **`Pred` has no decidable equality** in the published definitions, so two lowered predicates are compared here by their printed form. Deriving it is one word at the source.
4. **Private definitions.** The steps of `evaluateDoc` are private. Theorems about the whole function can be proved from outside by unfolding, as here; theorems about one step cannot be stated from outside. A correspondence proof of step 3 belongs beside the evaluator, at the source.

## The smallest realistic next target

> For every well-formed contract and every environment the evaluator accepts, the environment it builds is the settled environment of the specification.

With that and item 1, `evaluateDoc_is_definition` loses its existential and becomes the statement the specification makes: the evaluator computes the definition. Parsing (step 1) stays tested; it is a different kind of property, and two implementations agreeing on JSON is the usual evidence for it.

Typed terms (`WellTyped` as an index of the syntax) would make step 2 correct by construction and remove the `unknown` that a badly typed comparison yields. It is a larger change to the definition itself, and should follow, not precede, the target above.

## What was considered and not used

- **A refinement framework** (LeanMachines and similar). The chain is six functions composed once; each link is one lemma. A framework would add a dependency and a vocabulary and save nothing here. Worth another look if the registry's state machine is refined to an implementation.
- **Mathlib.** `Truth` has three values and the lemmas needed are four case splits. Nothing from Mathlib would shorten them.
- **Heavier automation.** The proofs use `simp`, `cases`, `split` and `rfl`. `evaluateDoc_decision` is `unfold`, then `split` at each branch, then `rfl`: it reads as what it is. `grind` and `aesop` were not needed, and `bv_decide` has no bit-vectors to decide.

## A reading of the text that this work found

The specification's table of predicate forms (section 4) says `and` and `or` take "at least one argument", and its refusal table says a contract that is "not JSON of the forms in sections 2 to 4" is `CONTRACT_MALFORMED`. Both public evaluators, Lean and Rust, refuse `{"and": []}` as `CONTRACT_ILL_FORMED`, the code for a static rule of section 5, and no published vector has an empty connective. The implementations agree with each other and, on one reading, not with the text. It is filed as [#30](https://github.com/dekrops/wvp/issues/30).

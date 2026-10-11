# Formal definitions (Lean 4)

The Lean definitions the specifications refer to, with the proofs about them. [Work Contract Language 1](../../protocols/work-contract/v1/SPEC.md) says that where its text and the definition of evaluation here disagree, this definition is right: `Verified/Contract/Semantics.lean` is that definition.

```sh
bash formal/lean/check.sh
```

Install Lean with elan first. `lean-toolchain` pins Lean 4.24.0, Lake has no third-party dependencies, and builds treat warnings as errors. The script builds everything, audits every declared theorem's transitive axioms, permitting only Lean's standard `propext`, `Classical.choice` and `Quot.sound`, and runs the reference evaluator over the shared corpus. There is no `sorry`, `admit`, custom `axiom` or `native_decide`.

These files are exported from the steward's source repository, like the specifications ([publication](../../governance/publication.md)). A model of one platform's ledger is kept there and is not part of the protocol; it is not published.

## Scope and authority

A proof here is a proof about the definition in the same file. It is not a proof about any implementation, about cryptography, or about a source system. What relates an implementation to these definitions is agreement on the shared corpus, which is evidence and not proof. Each section says what is proved, under which assumptions, and what is not.

`Order.lean` defines a contract, claim, observation, satisfaction predicate and executable Boolean verifier for a single state transition, the evaluator of [`wvp-0.1`](../../protocols/wvp/v0.1/SPEC.md). The order example proves APPROVED → SHIPPED succeeds, while another order or a disallowed starting state fails. `verification_sound` proves that Boolean acceptance entails the defined predicate for arbitrary inputs.

## Evidence semantics and chains

`Evidence.lean` separates authenticity from verification. A `Statement` is an issuer's assertion together with the outcome of signature checking (`authentic`); a `Model` says which issuers are authoritative for which sources; a statement is `Admissible` only if it is authentic **and** authoritative. `VerifiedBy` is the judgement ⟨c, E, M, Π⟩ ⊢ Verified(c): some admissible statement in E satisfies the contract under order-v1's `Satisfies`. `verifyAll` is the executable procedure, proved equivalent (`verifyAll_iff`). The theorems establish that verification always rests on the satisfaction predicate, that nothing verifies without authentic evidence, that adding inadmissible statements cannot verify a claim, and, concretely, that an authentic agent statement about a shipment does not verify the claim while the same observation from the authoritative source does.

`Chain.lean` abstracts statement chains to sequence numbers and digest tokens. `valid_chain_is_contiguous` proves that a chain valid from genesis is numbered 0, 1, 2, … in the presented order (no gaps, reordering or repeated steps). `truncation_is_undetectable` proves that every prefix of a valid chain is valid: the formal statement of the truncation limit that [Evidence Statement v1](../../docs/spec/evidence-statement-v1.md) describes. Signatures and hashes are assumed, not modelled.

| Lean abstraction                     | Reference implementation (not public)                                 | Deliberate abstraction                                                    |
| ------------------------------------ | --------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `Statement.authentic`                | `StatementVerifier.verify` succeeding (`AuthenticatedStatement`)      | The signature check itself, keys and registries                           |
| `Model.authoritative`                | Contract-snapshot source authority; evidence kinds a verifier accepts | A Boolean per issuer and source, not per predicate                        |
| `VerifiedBy`, `verifyAll`            | Admission, then the contract's verifier returning `Supported`         | One statement suffices; no contradiction precedence or required kinds     |
| `Link`, `Linked`, `ValidFromGenesis` | `Chain.verify` without an anchor                                      | Digest tokens instead of SHA-256; no issuer/stream or equivocation checks |

## Claim registry states

`Registry.lean` models the audit of a claim registry's log ([claim registration v1](../../protocols/claim-registration/v1/SPEC.md), section 4). Claims, agreements and units are numbers. `step` is the audit's rule for one entry, and `run` reads a log from its start. The checked theorems establish:

- `final_claims_persist`: a refused, expired, withdrawn or superseded claim keeps its identity and state, whatever entry follows;
- `disputes_keep_states`: opening or resolving a dispute changes no claim's state; it is recorded beside it;
- `claimant_cannot_close_disputed`: a claim under an open dispute cannot be withdrawn or replaced; the dispute is settled first;
- `accepted_log_units_exclusive`: in every log an audit accepts from its start, claims are identified uniquely, and claims that hold the same unit (open, answered with evidence, under an open dispute, or refused with the claimant's dispute of the refusal upheld) are the same claim. Opening a dispute of a refused claim is where this needs the audit's rule that no other claim holds the unit by then;
- `register_respects_limit`: a registration the audit accepts leaves at most the agreement's limit of open claims under it;
- `replacement_comes_next`: while a supersession awaits its replacement, the only entry accepted is the replacement's registration.

| Lean abstraction          | Reference implementation (not public)                            | Deliberate abstraction                                                                                                            |
| ------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `RegState`                | `ClaimState` in `modules/claim-registration`                     | Same six states                                                                                                                   |
| `RegDispute`              | `AuditedClaim.dispute` (`DisputeState`, or none)                 | Same states; terms, grounds, resolvers and signatures are not modelled                                                            |
| `RegClaim.unit`           | The pair of agreement `unitKey` and the claim's `unit` nullifier | One number                                                                                                                        |
| `step`                    | One entry of `RegistryLog.audit`                                 | Signatures, digests, documents, times, deadlines and dispute windows assumed checked; the replacement's agreement is not modelled |
| `RegEvent.register.limit` | The `openClaimLimit` of the agreement the claim names            | Carried by each registration                                                                                                      |

## Work Contract Language 1

`Verified/Contract` holds the formal definition of how a [Work Contract Language 1](../../protocols/work-contract/v1/SPEC.md) contract is evaluated, the proofs about that definition, and a second implementation of the whole language. This section is the handoff for whoever owns the formal semantics.

### Map

| File                     | Content                                                                                      | Status                               |
| ------------------------ | -------------------------------------------------------------------------------------------- | ------------------------------------ |
| `Truth.lean`             | Three truth values, `and`, `or`, `not`, n-ary forms                                          | Definition; every lemma proved       |
| `Semantics.lean`         | Types, values, terms, predicates, environments, `Pred.eval`, the decision                    | **The definition**                   |
| `Theorems.lean`          | Decisions, witnesses, completeness, monotonicity along `Extends`                             | Proved                               |
| `Typing.lean`            | Shapes, signatures, `WellTyped`, `Conforms`, type safety; acceptance by source               | Proved                               |
| `Limits.lean`            | Proved counterexamples: where the stability theorem's hypothesis ends                        | Proved                               |
| `Reference.lean`         | JSON reader, static rules, conformance, conflict resolution, closed kinds; calls `Pred.eval` | **Not proved.** Tested on the corpus |
| `ContractReference.lean` | Executable: runs the reference evaluator over `test-vectors/work-contract/v1`                | Run by `formal/lean/check.sh`        |

The model's environment (`Env`) is what evaluation sees **after** acceptance by source, conformance, conflict resolution and the computation of closed kinds. Those steps are specified (section 7, steps 1 to 6), implemented in `Reference.lean`, and outside every theorem.

### Proved

About `Pred.eval`, `decide` and `evaluate` in `Semantics.lean`, for every contract and environment of the model:

| Theorem                                       | Statement                                                                                                      |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `truth_tables`, `de_morgan`                   | The connectives are the published tables; De Morgan's laws hold in three values.                               |
| `supported_iff_all_true`                      | A decision is `supported` exactly when every requirement is `true`.                                            |
| `contradicted_iff_some_false`                 | It is `contradicted` exactly when some requirement is `false`.                                                 |
| `unknown_requirement_prevents_support`        | One `unknown` requirement prevents `supported`.                                                                |
| `exists_true_has_witness`                     | A true `exists` has a witness among the admitted records.                                                      |
| `exists_false_requires_closed`                | A false `exists` implies its kind is closed (and every record fails the body).                                 |
| `forall_true_requires_closed`                 | A true `forall` implies its kind is closed.                                                                    |
| `forall_false_has_counterexample`             | A false `forall` has a counterexample among the admitted records.                                              |
| `no_records_open_kind_is_unknown`             | With no records and a kind that is not closed, `exists` and `forall` are both `unknown`.                       |
| `eval_monotone`                               | Along `Extends`, `true` stays `true` and `false` stays `false`.                                                |
| `definite_decision_is_stable`                 | Along `Extends`, `supported` stays `supported` and `contradicted` stays `contradicted`.                        |
| `wellTyped_safe`                              | In a conforming environment a well-typed predicate only compares values of one shape, and orders only numbers. |
| `wellTyped_comparison_unknown_only_if_absent` | So a comparison is `unknown` only because a value is absent.                                                   |
| `unaccepted_fact_changes_nothing`             | In the model's acceptance filter, a record from a source not accepted for its kind changes no decision.        |
| `evaluation_is_deterministic`                 | One contract and one environment have one decision. True by construction.                                      |

### Assumptions each result rests on

`Extends earlier later` is the hypothesis of the two monotonicity theorems. It is a relation between two settled environments and it is narrow on purpose:

| Assumption in `Extends`                | What it means outside the model                                                                               | If it does not hold                                                                                                     |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Same inputs                            | The same claim inputs, **including the cutoff**.                                                              | Another cutoff is another question. No theorem relates the two answers.                                                 |
| Same policy parameters                 | The same contract.                                                                                            | Another contract, another digest; nothing is claimed.                                                                   |
| Every earlier record is still a record | Evidence is append-only **and** nothing admitted later conflicts with it.                                     | A conflicting record removes records from the settled environment. Decisions can change, including to the opposite one. |
| A closed kind stays closed             | Completeness statements are not withdrawn.                                                                    | `withdrawn_completeness_loses_the_decision`: definite decisions become undetermined.                                    |
| A closed kind gains no record          | **Every completeness statement was true**: the source really had no other record of that kind for this claim. | `late_record_in_complete_listing_overturns_support` and `…_contradiction`: the decision can reverse.                    |

So the precise reading of `definite_decision_is_stable` is: _if nothing admitted later conflicts with what was admitted before, no completeness statement was wrong or is withdrawn, and the question (inputs, cutoff, contract) is unchanged, then a supported or contradicted decision is not changed by admitting more evidence._ It is not a statement that decisions are final.

The cases outside the hypothesis are not hypothetical. `Limits.lean` proves three of them inside the model, and `ContractLanguageSuite` ("what stability does not cover") pins the others against the Scala evaluator: a late conflicting record under each conflict policy, a record arriving in a listing declared complete, and the same evidence under a later cutoff.

Other assumptions:

- **`wellTyped_safe` assumes `Conforms`** (every present value has its declared shape) and `Bound` (the scope matches the typing context). It is not proved that the reference evaluator establishes either, or that its static checker implies `WellTyped`.
- **`unaccepted_fact_changes_nothing` is about `accepted`**, the filter defined in `Typing.lean`. The reference evaluator and the Scala and JavaScript evaluators each implement their own filter.
- **Late-arriving records.** A record's `at` field is data. The model has no notion of when a record was observed or admitted, so "a record dated before the cutoff that arrives after the decision" is, for the model, simply a larger environment: covered by monotonicity if its kind was open, and a violated completeness statement if its kind was closed.
- **Sources are trusted for what they say.** Nothing here, and nothing anywhere, establishes that a record or a completeness statement is true.

### Not proved

- **Nothing about Scala or JavaScript.** They are separate programs. What relates them to this model is agreement on a corpus (below).
- **Nothing about `Reference.lean`**: reading JSON, the static rules, conformance, conflict resolution, closed kinds and the cutoff comparison, and `lower` (lists to binary connectives). It contains `partial` definitions.
- **Type safety is for shapes** (text, boolean, number), not for currency and scale.
- **Canonical bytes and digests** are outside the model.
- **The work bound** (specification 7, step 4) is outside the model. `eval_monotone` and `definite_decision_is_stable` are about evaluation (7.7, 7.8). The bound counts every fact in the environment, so admitting one more record, even one that evaluation ignores, can turn a decision into a `WORK_LIMIT` refusal (corpus cases 91 and 92). A refusal is not a decision; nothing here says a decision survives as a decision when evidence is added.

### Trust boundary between the three implementations

| Layer                                                                             | Lean                                                                | Scala                                                | JavaScript          |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------- | ------------------- |
| Truth tables, quantifiers, decision (specification 7.7, 7.8)                      | **Defined and proved** (`Semantics`, `Theorems`)                    | Implemented; tested                                  | Implemented; tested |
| Typing (5, rule 7)                                                                | Judgement defined, safety proved; the checker that runs is unproved | Implemented; tested                                  | Implemented; tested |
| Reading JSON, other static rules, limits (2 to 5)                                 | Implemented, unproved                                               | Implemented; tested                                  | Implemented; tested |
| Acceptance, conformance, work bound, conflicts, closed kinds, cutoff (7.1 to 7.6) | Implemented, unproved                                               | Implemented; tested                                  | Implemented; tested |
| Canonical form and digest (9)                                                     | Not modelled                                                        | Implemented; shared vectors with Rust and JavaScript | Implemented         |
| Packages, signatures, admission of signed statements                              | Not modelled                                                        | Implemented                                          | Implemented         |

The only link across columns is the shared corpus in `test-vectors/work-contract/v1`: 82 hand-written cases and 560 generated ones, which each implementation must reproduce on every change (`formal/lean/check.sh`, `ContractLanguageSuite`, and `npm run test:conformance` for JavaScript). Agreement on a corpus is evidence, not proof, and all implementations and the corpus have one author.

A relying party who verifies a package runs an implementation that is not this one: Scala, JavaScript, or the public Rust implementation. What they are trusting is therefore: that implementation; the specification it was written from; and, as supporting evidence only, that the specification's evaluation rules have a formal definition with the properties above and that the implementation agrees with it on the corpus.

### Unresolved semantics

Questions the language does not answer yet. Each needs a decision before a proof.

1. **Corrections.** A source that corrects a record emits a second record with the same key. Today that is a conflict, settled by the contract's policy; "the later statement supersedes" is not expressible, because records carry no admission order.
2. **Scope of completeness.** A completeness statement says "every record of this kind I have for this claim". "For this claim" is not formal: nothing ties the statement to the claim's inputs.
3. **Completeness and time.** A kind is closed when a statement's `asOf` is not before the cutoff. Nothing relates `asOf` to the times inside the records, so a record dated after `asOf` in a closed kind is accepted without comment.
4. **Observation time against the cutoff.** A record dated before the cutoff but observed long after it is admitted like any other. Whether a contract should be able to bound observation time is open.
5. **Conflicts across kinds.** Conflict detection is per kind and key. Two records of different kinds that cannot both be true are not a conflict.
6. **Partial information within a record.** An absent optional field is `unknown`. There is no way to say "the source states this field has no value".
7. **Text.** Equality is exact, with no normalization; whether identifiers should be compared after normalization is a contract-authoring question the language does not address.

### Highest-value next proofs

In order:

1. **Connect the checker to the judgement.** Prove `Reference.typed doc [] p → (lower p).WellTyped sig []` for the signature read from `doc`, and that `evaluateDoc` builds an environment with `Conforms`. This makes `wellTyped_safe` a statement about the reference evaluator.
2. **Prove `lower` correct** against an n-ary evaluation of `WPred`, or make `Pred` n-ary and redo the inductions with a nested induction principle.
3. **Model conflict resolution and closed kinds**, then state the true stability theorem at the level of admitted records: which additions are extensions of the settled environment (records with new keys in open kinds), and that an unsettled conflict never yields a definite quantifier over its kind.
4. **The cutoff.** Model `asOf` and prove that a kind is closed only by a statement at or after the cutoff; then that records whose compared time is after the cutoff do not change a requirement that bounds that time by the cutoff.
5. **Type safety for units**: give values their currency and scale in the model.
6. **Totality of the reference evaluator**: replace the `partial` definitions with structurally recursive ones.

Do not extend the language (arithmetic, durations, counting) without extending `Semantics.lean` and the corpus in the same change.

### Working here

```sh
bash formal/lean/check.sh      # build, audit every theorem's axioms, run the corpus
```

Rules, enforced by that script: no `sorry`, `admit`, custom `axiom` or `native_decide` anywhere under `Verified/`; every `theorem` must be listed in `Verified/Audit.lean`; only `propext`, `Classical.choice` and `Quot.sound` may appear among a theorem's axioms. A theorem is declared directly inside the file's first namespace so that the audit can find it.

The corpus is generated by the reference implementation, which is not public, and frozen. If the reference evaluator disagrees with a case, first decide from the specification which side is wrong.

## Trust and exclusions

An observation reporting SHIPPED does not establish physical shipment. Source authenticity, honesty, authorization and provenance integrity are external obligations; `Satisfies` checks a claimed source name and supplied times, not those obligations. Hashes are abstract strings, not proof of origin.

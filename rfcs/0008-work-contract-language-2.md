# RFC 0008: Work Contract Language 2: arithmetic and aggregates

|            |                                                                                             |
| ---------- | ------------------------------------------------------------------------------------------- |
| RFC        | 0008                                                                                        |
| Status     | Review, from 2026-11-10 (the review period runs at least until 2026-11-24)                  |
| Author     | Zin Nam                                                                                     |
| Created    | 2026-10-29                                                                                  |
| Affects    | New: `work-contract-2`. `work-contract-1` is unchanged. A WVP package version to carry it.  |
| Supersedes | Nothing                                                                                     |

Work Contract Language 1 can say who approved what, and when. It cannot compute with an amount or count records, so the controls that matter most in a system of record (an invoice within tolerance of its order, nothing paid twice, two approvers who are not the creator) cannot be stated. This RFC proposes `work-contract-2`: Language 1 with exact integer arithmetic on terms and with `count`, `count` of distinct values and `sum` over the records of a kind. An aggregate has a value only over a kind a source declared complete, so missing evidence still never becomes a pass. A Lean model of the new evaluation is in [`0008/formal`](0008/formal), with checked proofs that it extends Language 1 exactly and keeps Language 1's stability under added evidence.

## Motivation

[Work Contract Language 1, section 12](../protocols/work-contract/v1/SPEC.md#12-not-in-this-version) lists what it leaves out, first among them "arithmetic (so a variance must be a recorded field; it cannot be computed from two amounts)" and "aggregation and counting". Both gaps show up as soon as the protocol is used on a transactional system rather than on code review. Each of these is a control a buyer asks for, and none can be written today:

| Control                                                | Needs                          |
| ------------------------------------------------------ | ------------------------------ |
| The invoice is within 1 % of its purchase order        | subtraction, absolute value, scaling |
| Allocated payments never exceed the invoice amount     | a sum over a kind              |
| At least two approvers, neither of them the creator    | a count over a kind            |
| The order confirmation's quantity is within 10 %       | arithmetic                     |
| Paid within the payment term (n days of the due date)  | arithmetic on times            |

The workaround in Language 1 is to have the source compute the value (a recorded `variance` field). That moves the judgement into the system being checked: the contract then verifies that the source said the variance was small, not that it was. The sum and the count cannot be expressed even that way, because a count or a sum is a statement about a set of records, not about one.

N-of-M approval can be written in Language 1 for a fixed N by nesting N quantifiers with pairwise inequalities. That works for N = 2 and stops scaling at the nesting limit of 3.

## What changes

A new language, identifier `work-contract-2`, evaluation semantics `kleene-1` unchanged. Everything in Language 1 is part of it, with the same meaning. It adds:

**Arithmetic terms.** Every number in the language is already a whole number of its type's smallest unit (`int`, `time`, `decimal` of a scale, `money` of a currency and scale), so arithmetic is exact integer arithmetic. There is no division and no rounding.

| Form (proposed wire form)            | Value                                 | Static rule                                                             |
| ------------------------------------ | ------------------------------------- | ----------------------------------------------------------------------- |
| `{"add": [term, term]}`              | the sum                               | both operands of one numeric type; the result has that type             |
| `{"sub": [term, term]}`              | the difference                        | both operands of one numeric type, with that type; or both `time`, giving an `int` of seconds |
| `{"scale": "<number>", "of": term}`  | the term times a whole number (a number string, as every value) | the term has a numeric type; the result has that type                   |
| `{"abs": term}`                      | the absolute value                    | the term has a numeric type; the result has that type                   |

The **numeric types** are `int`, `decimal` (of one scale) and `money` (of one currency and scale). `time` is not one: it takes part in arithmetic only as `time − time`. A time cannot be added, scaled, given an absolute value, or have a number subtracted from it; "paid within 30 days of the due date" is `paidAt − dueAt ≤ 30 × 86 400`.

A term whose operand has no value (an absent optional field, an input not supplied) has no value, as in Language 1, and a comparison with it is `unknown`. "Within 1 %" is `100 × |a − b| ≤ b`, with no fraction anywhere. Where `b` can be negative (a credit note), the bound is `|b|`: `100 × |a − b| ≤ |b|`; with `b` alone it is never `TRUE` for a negative `b`.

**Aggregate predicates.**

```json
{ "aggregate": "count", "of": "a", "in": "approval", "where": <predicate>, "cmp": "ge", "than": <term> }
{ "aggregate": "count", "distinct": "approver", "of": "a", "in": "approval", "where": <predicate>, "cmp": "ge", "than": <term> }
{ "aggregate": "sum", "field": "amount", "of": "m", "in": "paymentMatch", "where": <predicate>, "cmp": "le", "than": <term> }
```

`count` is the number of records of the kind for which the body is `TRUE`; with `distinct`, it is the number of distinct values the named field takes over those records (how many approvers, not how many approvals), two values being the same when Language 1's `eq` holds between them; `sum` is the sum of a numeric field over those records, with the field's type. The comparison is with `than`, under Language 1's comparison rules.

An aggregate **has a value only when the kind is closed** (a completeness statement, as Language 1 section 6 defines it) **and the body is `TRUE` or `FALSE` for every record of it**. Otherwise the predicate is `unknown`. Over a listing nobody declared complete, a count is a lower bound and a sum is not a sum; this version uses neither (see the open questions).

**Static rules**, in addition to Language 1 section 5: an aggregate's variable is bound in its body only, as a quantifier's is; its nesting counts toward the quantifier depth limit of 3; `sum` names a non-optional field of a numeric type of the kind; `distinct` appears on `count` only, and names a non-optional field of the kind, of any type; the operand types of arithmetic and of `than` follow the table above. `scale`'s factor is a value like any other: a whole number strictly between −2⁶³ and 2⁶³, or the contract is `CONTRACT_ILL_FORMED` (vector 281); the 128-bit bound below rests on it. Each `add`, `sub`, `scale` and `abs` counts as a node, with the predicates, toward the limit of 512 nodes (static rule 9) and toward _s_ in the work bound (section 7, step 4), and Language 1's read depth of 64 levels counts them too. A Language 1 contract has none, so its count is unchanged.

**One record per key.** Language 1 already settles it ([section 7, step 5](../protocols/work-contract/v1/SPEC.md#7-evaluation)): accepted facts of one kind with equal key fields describe one object, are one record if their fields are identical, and are a conflict if they differ. So the environment evaluation sees lists each record of a kind once, and an aggregate counts records, not listings. Language 2 keeps that step unchanged and states it as what aggregates rely on. A plain `count` therefore counts what the kind's key identifies: approvals, for an `approval` keyed by its own identifier. A contract that counts people uses `distinct` over the field that names them (`"distinct": "approver"`), and the kind keeps the key its source gives it. Keying the kind by the person instead (by run and approver) also counts each person once, but a person who approves again at another time then reports two different facts with one key: a conflict, which leaves the count `unknown` under `conflicts: unknown`.

**Range.** Every value arithmetic computes must lie strictly between −2⁶³ and 2⁶³, as every value on the wire does: the value of each `add`, `sub`, `scale` and `abs` node, and the value of each aggregate. One that does not makes the evaluation refuse with `ARITHMETIC_RANGE`. Inside a `sum` the running total is exact and only the sum is checked, because the order of a kind's records is the listing's, not the contract's, and a check on partial totals could depend on it. A term's order is written in the contract, so each of its nodes is checked. With every operand in range, nothing an implementation computes needs more than 128 bits: a product of two values below 2⁶³ is below 2¹²⁶, and a sum of at most 10 000 of them is below 2⁷⁷. A refusal, not `unknown`: `unknown` says the evidence was not enough, which would be false.

**What is evaluated.** Language 1 has no refusal during evaluation, so an implementation may skip what cannot change a value. `ARITHMETIC_RANGE` is found during evaluation, so whether a term is evaluated changes the outcome. Language 2 fixes it: every term of every requirement is evaluated, under every binding of every quantifier and aggregate, whatever the value of the predicates around it. The bindings are the records Language 1's step 5 keeps (section 7): a fact it does not use, such as both facts of a conflict settled as `unknown`, or under `source-order` the facts that lose, is never a binding, and no term is evaluated on it (vectors 278, 279). That includes the second disjunct of `or(TRUE, …)`, and a record whose body is already `FALSE` at its first conjunct. Each node that has a value is checked, whatever its parent: in `add(add(a, b), x)` with `x` absent, the outer `add` has no value, but the inner one has, and is checked (vector 280). A node without a value (an absent operand) computes nothing and is not checked. An aggregate without a value (an open kind, or a body `unknown` for some record) computes no count or sum, so nothing of it is checked; its body's terms are still evaluated for every record. An implementation may evaluate lazily if it refuses exactly when this full evaluation would.

## Outcomes that change

None for any published input: `work-contract-1` and its vectors are untouched. `work-contract-2` is a new identifier in a new directory, with its own vectors ([RFC 0001](0001-standards-process.md), invariant 2). An implementation of Language 1 refuses a `work-contract-2` contract as `CONTRACT_ILL_FORMED` (its `language` is not Language 1's identifier, static rule 1; published case `27-contract-other-language`), and the reverse: versions are never interchanged (invariant 3).

The Lean model proves that a Language 1 contract, written in Language 2's form, decides every environment exactly as it does in Language 1 (`same_decision_as_language_1`). A producer may therefore move a contract to Language 2 without changing what it decides. Doing so is a new contract with a new digest, which its approvers sign again.

## Compatibility

- **Producers** keep producing Language 1 contracts until they need the new forms. Nothing changes for them otherwise.
- **Verifiers** that implement only Language 1 refuse Language 2 contracts. They do not misread them.
- **Packages.** WVP v0.2 names `work-contract-1`, and a v0.2 verifier refuses a package whose contract is another language. A package that carries `work-contract-2` would turn that refusal into a decision, which is a change of outcome and therefore a new package version ([RFC 0001](0001-standards-process.md), invariant 2), not a revision of v0.2. So Language 2 reaches packages with [RFC 0003](0003-wvp-0.3.md) or with a small version of its own, whichever is accepted first; the language itself does not have to wait for either.
- **Relying parties** see no change in what a decision means: `SUPPORTED`, `CONTRADICTED` and `UNDETERMINED` keep Language 1's definitions, and `UNDETERMINED` still means the evidence was not enough.

## Vectors

The proposed vectors are in [`0008/vectors`](0008/vectors/work-contract/v2/README.md), written by [`0008/generate.py`](0008/generate.py). For every case with a result, `0008/formal/WCL2/Vectors.lean` states that the model gives exactly its expected requirement values and decision, proved by `decide` and audited by `check.sh`; the refusals are not in the model, and the README lists them. On acceptance they become `test-vectors/work-contract/v2`, which will hold, at least:

- every Language 1 case, restated in Language 2's form, with its Language 1 expectation;
- arithmetic: within and outside a tolerance, `time − time`, an absent operand (`unknown`), `scale` by a negative factor, `abs` of a negative amount;
- aggregates: `count` and `sum` over a closed kind with zero, one and several matching records; over an open kind (`unknown`); with one body `unknown` (`unknown`); a record of another kind or not matching the body (not counted);
- the worked examples of the Lean model (tolerance, overpayment by one cent, open listing, four eyes), and the same approver under two approval identifiers, counted twice by `count` and once by `count` with `distinct`, with a re-approval counted once without a conflict;
- refusals: operands of two currencies or scales, `time + time`, `sum` of a text or optional field, an aggregate variable used outside its body, depth over 3 with aggregates, the arithmetic range on a sum and on an intermediate term, a term out of range under `or(TRUE, …)` and for a record the body does not select, `scale`, `abs` and subtraction of a number on a time, arithmetic nodes over the node limit, `distinct` over an optional or undeclared field, and `distinct` on `sum`;
- a `sum` over an open kind whose values would leave the range: `unknown`, not a refusal, because it computes nothing;
- terms evaluated only on the records step 5 keeps: an out-of-range fact in a conflict settled as `unknown` (`UNDETERMINED`), and one that loses under `source-order` (decided on the preferred fact);
- an out-of-range node under a parent with an absent operand (a refusal), and `scale` by a factor out of range (`CONTRACT_ILL_FORMED`).

## Security considerations

This RFC changes what a verified result may be relied on for, so it needs security review ([RFC 0001](0001-standards-process.md), section 9.1). Reviewer other than the author: Srishti (GitHub `SrishtiCode`), in this RFC's pull request.

- **Completeness carries more weight.** An aggregate's value rests on a completeness statement, as a false `exists` or a true `forall` does in Language 1. A source that declares a listing complete when it is not can make a sum too small or a count too low. This is the same trust Language 1 already places in completeness statements, now used by more requirements. Who may make one for which kind remains the relying party's registry, never the package (invariant 7).
- **No new source of truth.** Arithmetic computes from accepted values only. It removes a reason to trust a source's own computed fields.
- **Work.** An aggregate visits the records of one kind once per binding of the enclosing variables, as a quantifier does; the work bound (Language 1 section 7, step 4) covers it unchanged. Arithmetic is bounded by the term's size.
- **Range.** Values on the wire lie strictly between −2⁶³ and 2⁶³. A sum of many large amounts, or a term over large values, can leave that range; the evaluation then refuses (`ARITHMETIC_RANGE`) rather than wrap or saturate. Every term node and every aggregate value is checked, partial totals inside a `sum` are not, and every term is evaluated (section "What changes"), so every implementation refuses the same inputs. `ARITHMETIC_RANGE` is found during evaluation, so it comes after every refusal of Language 1's table (section 8), whose order is unchanged. The model uses unbounded integers, so it says nothing about the refusal itself.
- **A refusal from more evidence.** `definite_decision_is_stable` is about evaluation. `ARITHMETIC_RANGE` is outside it, as `WORK_LIMIT` is in Language 1 (its section 13): a source accepted for a kind can admit a fact whose amount puts some term out of range, and the evaluation then refuses where it decided before. Such a source can force a refusal, never a different decision. A relying party should therefore accept a source for a kind that is counted, summed or used in arithmetic only from a system it trusts to keep its values in range, as it already should for the work bound.
- **Counting listings instead of records.** If a source could list the same approval twice, it could pass a count with one person. Language 1's step 5 makes equal-key facts one record (or a conflict), so that cannot reach evaluation. The model shows both the danger and why it is excluded (`duplicate_approval_counts_twice`, `duplicate_listing_is_not_distinct`).
- **Counting records instead of people.** A plain `count` over a kind keyed by something other than what the contract means to count still counts records: one person approving under two identifiers passes a four-eyes `count` (vector 244). Language 2 has no warnings, and the typing cannot tell which field a contract means to count, so this is not a refusal. A contract that counts people uses `distinct` (vector 247), and reviewers of a contract check that its counts do.
- **One person under two identifiers.** `distinct` compares values. If a source names one person by two values (`lea` and `l.mueller`), they are two approvers. Mapping identities is the source's or the relying party's registry's concern, outside the language.

## Formal semantics

`0008/formal` is a Lake package that depends on `formal/lean` and reuses Language 1's values, records, environments and truth values. `./check.sh` builds it and audits every theorem's axioms under the rules of `formal/lean/check.sh`: no `sorry`, `admit`, custom axiom or `native_decide`, and only `propext`, `Classical.choice` and `Quot.sound`. 32 theorems:

| Theorem | Statement |
| --- | --- |
| `extends_language_1`, `same_decision_as_language_1` | A Language 1 predicate has the same value in Language 2, in every environment and scope; a Language 1 contract has the same decision. |
| `aggregate_value_requires_closed`, `aggregate_settled_requires_closed` | An aggregate comparison that is `TRUE` or `FALSE` was taken over a closed kind, with every body settled. |
| `aggregate_open_kind_is_unknown` | Over a kind no source declared complete, every aggregate comparison is `unknown`, however many records were seen. |
| `exists_true_has_witness`, `exists_false_requires_closed`, `forall_true_requires_closed`, `forall_false_has_counterexample` | As in Language 1, for Language 2's quantifiers. |
| `closed_listing_is_reordered` | Along `Extends`, between environments that list each record once, a closed kind is listed later as a reordering of what it was. |
| `sumOf_perm`, `definite_perm`, `mem_uniq`, `nodup_uniq`, `uniq_perm`, `value_perm` | A count, a distinct count or a sum does not depend on the order its records are listed in. |
| `term_eval_extends`, `settled_bodies_kept` | Terms, arithmetic included, do not depend on records; bodies settled over a listing stay so over a reordering of it. |
| `eval_monotone`, `definite_decision_is_stable` | Along a settled extension of the environment, a `TRUE` requirement stays `TRUE`, a `FALSE` one stays `FALSE`, and a supported or contradicted decision stays so, aggregates included. |
| `within_tolerance_and_paid_once`, `overpaid_is_contradicted`, `open_listing_is_undetermined`, `two_other_approvers_suffice`, `creator_approval_not_counted` | The worked examples, decided by the model. |
| `same_approver_under_two_ids_is_counted_twice`, `two_ids_of_one_approver_are_distinct` | Where the key decides: an approval keyed by its own identifier is two records for one approver who approves twice. Both are listed once, so the environment is `Distinct`, and the count is 2. One record per key protects a count only when the kind is keyed by what it counts. |
| `same_approver_under_two_ids_is_one_distinct_approver`, `reapproval_counts_one_approver` | The same approvals counted with `distinct "approver"`: Lea under two identifiers is one approver, so four eyes is contradicted; Lea approving again under a new identifier, with Max, is two approvers, with no conflict. |
| `duplicate_approval_counts_twice`, `duplicate_listing_is_not_distinct` | The model counts listings: one approval listed twice passes four eyes. Such an environment lists a record twice, so it is not `Distinct`: Language 1's step 5 never produces one. |

**The hypothesis to read first.** Stability is proved along `Settled`: Language 1's `Extends`, between two environments that each list a record once (`Distinct`). Nothing more is assumed: that a closed kind is then listed as a reordering of what it was is proved (`closed_listing_is_reordered`), and that counts, distinct counts and sums do not depend on the order is proved (`value_perm`). `Distinct` is what Language 1's step 5 already produces: one record per key.

**Not covered by any proof:** the typing rules of arithmetic (units, currencies, `time − time`), the numeric range and which terms are evaluated for it, the node count, the wire form, the work bound, and every implementation. The Scala, JavaScript and Rust implementations are tied to this model by the shared vectors, as they are for Language 1.

## Alternatives

- **Computed fields from the source** (today's workaround). It keeps the language small, but the contract then checks the source's arithmetic claim rather than the arithmetic. It cannot express counts or sums at all.
- **A general expression language** (CEL, Rego, or a subset of JavaScript). More expressive, but evaluation is no longer bounded and three-valued by construction, and the proofs that a contract's meaning is stable would have to be redone for a much larger language. The point of this language is that a decision can be reproduced and reasoned about.
- **Rational numbers and division.** Percentages read more naturally, but every division needs a rounding rule, and rounding rules are where two implementations disagree. Scaling both sides by whole numbers expresses the same tolerances exactly.
- **Counting over open kinds as lower bounds.** `count ≥ n` is monotone even without a completeness statement: n witnesses can only grow. It is attractive for approvals. It is left open, because it makes `count` mean two different things depending on the comparison.

## Open questions

Decided in review (Srishti, in this RFC's pull request), and moved into the sections above:

- *Range:* a refusal, `ARITHMETIC_RANGE`, not `unknown`. Inside a `sum` the total is exact and only the sum is checked, so the listing's order cannot change the outcome. Each term node is checked, since the contract fixes a term's order, and 128 bits then suffice. Every term is evaluated, so a short-circuit cannot change whether an evaluation refuses.
- *Settled listings:* proved, not assumed, from one record per key (`Distinct`).
- *Durations:* `time − time` in seconds is enough; "within 30 days" is `30 × 86 400`.
- *The package version:* a new one, with RFC 0003 or on its own; not a revision of v0.2.
- *Counting the same record twice:* excluded by one record per key, which Language 1's step 5 already gives.
- *Counting the same person twice* (raised by Srishti in review, `same_approver_under_two_ids_is_counted_twice`): `count` with `distinct` over the field that names them. A static rule that a counted kind's key must cover what is counted was the alternative; it was not chosen, because `count` names no field to check the key against, and keying by the person turns a re-approval into a conflict (vector 246).

Still open:

1. **Lower-bound counts** over open kinds (`count ≥ n` is monotone without a completeness statement). Wanted for approvals, but as a separate RFC, so that `count` always means one thing.

## Decision

Not yet decided. There is one maintainer ([`governance/MAINTAINERS.md`](../governance/MAINTAINERS.md)), so the decision will rest on the review period alone and say so ([RFC 0001](0001-standards-process.md), section 12.3), and it will say whether there was review from outside the steward (section 7, rule 4).

## Implementation

Not yet implemented. The Lean model is in [`0008/formal`](0008/formal).

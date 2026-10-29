# RFC 0008: Work Contract Language 2: arithmetic and aggregates

|            |                                                                                             |
| ---------- | ------------------------------------------------------------------------------------------- |
| RFC        | 0008                                                                                        |
| Status     | Draft                                                                                       |
| Author     | Zin Nam                                                                                     |
| Created    | 2026-10-29                                                                                  |
| Affects    | New: `work-contract-2`. `work-contract-1` is unchanged. A WVP package version to carry it.  |
| Supersedes | Nothing                                                                                     |

Work Contract Language 1 can say who approved what, and when. It cannot compute with an amount or count records, so the controls that matter most in a system of record (an invoice within tolerance of its order, nothing paid twice, two approvers who are not the creator) cannot be stated. This RFC proposes `work-contract-2`: Language 1 with exact integer arithmetic on terms and with `count` and `sum` over the records of a kind. An aggregate has a value only over a kind a source declared complete, so missing evidence still never becomes a pass. A Lean model of the new evaluation is in [`0008/formal`](0008/formal), with checked proofs that it extends Language 1 exactly and keeps Language 1's stability under added evidence.

## Motivation

[Work Contract Language 1, section 12](../protocols/work-contract/v1/SPEC.md#12-not-in-this-version) lists what it leaves out, first among them "arithmetic (so a variance must be a recorded field; it cannot be computed from two amounts)" and "aggregation and counting". Both gaps show up as soon as the protocol is used on a transactional system rather than on code review. Each of these is a control a buyer asks for, and none can be written today:

| Control                                                | Needs                          |
| ------------------------------------------------------ | ------------------------------ |
| The invoice is within 1 % of its purchase order        | subtraction, absolute value, scaling |
| Allocated payments never exceed the invoice amount     | a sum over a kind              |
| At least two approvers, neither of them the creator    | a count over a kind            |
| The order confirmation's quantity is within 10 %       | arithmetic                     |
| Paid within the payment term (n days of the due date)  | arithmetic on times            |

The workaround in Language 1 is to have the source compute the value (a recorded `variance` field). That moves the judgement into the system being checked: the contract then verifies that the source said the variance was small, not that it was. Two of the three controls cannot be expressed even that way, because a count or a sum is a statement about a set of records, not about one.

N-of-M approval can be written in Language 1 for a fixed N by nesting N quantifiers with pairwise inequalities. That works for N = 2 and stops scaling at the nesting limit of 3.

## What changes

A new language, identifier `work-contract-2`, evaluation semantics `kleene-1` unchanged. Everything in Language 1 is part of it, with the same meaning. It adds:

**Arithmetic terms.** Every number in the language is already a whole number of its type's smallest unit (`int`, `time`, `decimal` of a scale, `money` of a currency and scale), so arithmetic is exact integer arithmetic. There is no division and no rounding.

| Form (proposed wire form)            | Value                                 | Static rule                                                             |
| ------------------------------------ | ------------------------------------- | ----------------------------------------------------------------------- |
| `{"add": [term, term]}`              | the sum                               | both operands of one numeric type; the result has that type             |
| `{"sub": [term, term]}`              | the difference                        | one numeric type, except `time − time`, which is an `int` of seconds    |
| `{"scale": number, "of": term}`      | the term times a whole number          | the result has the term's type                                          |
| `{"abs": term}`                      | the absolute value                    | a numeric type                                                          |

A term whose operand has no value (an absent optional field, an input not supplied) has no value, as in Language 1, and a comparison with it is `unknown`. "Within 1 %" is `100 × |a − b| ≤ b`, with no fraction anywhere.

**Aggregate predicates.**

```json
{ "aggregate": "count", "of": "a", "in": "approval", "where": <predicate>, "cmp": "ge", "than": <term> }
{ "aggregate": "sum", "field": "amount", "of": "m", "in": "paymentMatch", "where": <predicate>, "cmp": "le", "than": <term> }
```

`count` is the number of records of the kind for which the body is `TRUE`; `sum` is the sum of a numeric field over those records, with the field's type. The comparison is with `than`, under Language 1's comparison rules.

An aggregate **has a value only when the kind is closed** (a completeness statement, as Language 1 section 6 defines it) **and the body is `TRUE` or `FALSE` for every record of it**. Otherwise the predicate is `unknown`. Over a listing nobody declared complete, a count is a lower bound and a sum is not a sum; this version uses neither (see the open questions).

**Static rules**, in addition to Language 1 section 5: an aggregate's variable is bound in its body only, as a quantifier's is; its nesting counts toward the quantifier depth limit of 3; `sum` names a non-optional field of a numeric type of the kind; the operand types of arithmetic and of `than` follow the table above. Every node counts toward the 512-node limit.

## Outcomes that change

None for any published input: `work-contract-1` and its vectors are untouched. `work-contract-2` is a new identifier in a new directory, with its own vectors ([RFC 0001](0001-standards-process.md), invariant 2). An implementation of Language 1 refuses a `work-contract-2` contract as `CONTRACT_MALFORMED`, and the reverse: versions are never interchanged (invariant 3).

The Lean model proves that a Language 1 contract, written in Language 2's form, decides every environment exactly as it does in Language 1 (`same_decision_as_language_1`). A producer may therefore move a contract to Language 2 without changing what it decides. Doing so is a new contract with a new digest, which its approvers sign again.

## Compatibility

- **Producers** keep producing Language 1 contracts until they need the new forms. Nothing changes for them otherwise.
- **Verifiers** that implement only Language 1 refuse Language 2 contracts. They do not misread them.
- **Packages.** WVP v0.2 names `work-contract-1`. Carrying a Language 2 contract needs a package version that names `work-contract-2` (with [RFC 0003](0003-wvp-0.3.md), or a revision of it). Until then a Language 2 contract cannot be verified from a package.
- **Relying parties** see no change in what a decision means: `SUPPORTED`, `CONTRADICTED` and `UNDETERMINED` keep Language 1's definitions, and `UNDETERMINED` still means the evidence was not enough.

## Vectors

`test-vectors/work-contract/v2` will hold, at least:

- every Language 1 case, restated in Language 2's form, with its Language 1 expectation;
- arithmetic: within and outside a tolerance, `time − time`, an absent operand (`unknown`), `scale` by a negative factor, `abs` of a negative amount;
- aggregates: `count` and `sum` over a closed kind with zero, one and several matching records; over an open kind (`unknown`); with one body `unknown` (`unknown`); a record of another kind or not matching the body (not counted);
- the worked examples of the Lean model (tolerance, overpayment by one cent, open listing, four eyes);
- refusals: operands of two currencies or scales, `time + time`, `sum` of a text or optional field, an aggregate variable used outside its body, depth over 3 with aggregates, the arithmetic range (once decided, below).

## Security considerations

This RFC changes what a verified result may be relied on for, so it needs security review ([RFC 0001](0001-standards-process.md), section 9.1).

- **Completeness carries more weight.** An aggregate's value rests on a completeness statement, as a false `exists` or a true `forall` does in Language 1. A source that declares a listing complete when it is not can make a sum too small or a count too low. This is the same trust Language 1 already places in completeness statements, now used by more requirements. Who may make one for which kind remains the relying party's registry, never the package (invariant 7).
- **No new source of truth.** Arithmetic computes from accepted values only. It removes a reason to trust a source's own computed fields.
- **Work.** An aggregate visits the records of one kind once per binding of the enclosing variables, as a quantifier does; the work bound (Language 1 section 7, step 4) covers it unchanged. Arithmetic is bounded by the term's size.
- **Range.** Values on the wire lie strictly between −2⁶³ and 2⁶³. A sum of many large amounts can leave that range. How that is handled is open (below). The model uses unbounded integers, so it says nothing about it.

## Formal semantics

`0008/formal` is a Lake package that depends on `formal/lean` and reuses Language 1's values, records, environments and truth values. `./check.sh` builds it and audits every theorem's axioms under the rules of `formal/lean/check.sh`: no `sorry`, `admit`, custom axiom or `native_decide`, and only `propext`, `Classical.choice` and `Quot.sound`. 19 theorems:

| Theorem | Statement |
| --- | --- |
| `extends_language_1`, `same_decision_as_language_1` | A Language 1 predicate has the same value in Language 2, in every environment and scope; a Language 1 contract has the same decision. |
| `aggregate_value_requires_closed`, `aggregate_settled_requires_closed` | An aggregate comparison that is `TRUE` or `FALSE` was taken over a closed kind, with every body settled. |
| `aggregate_open_kind_is_unknown` | Over a kind no source declared complete, every aggregate comparison is `unknown`, however many records were seen. |
| `exists_true_has_witness`, `exists_false_requires_closed`, `forall_true_requires_closed`, `forall_false_has_counterexample` | As in Language 1, for Language 2's quantifiers. |
| `term_eval_extends`, `settled_bodies_kept` | Terms, arithmetic included, do not depend on records; a listing whose bodies were settled stays settled. |
| `eval_monotone`, `definite_decision_is_stable` | Along a settled extension of the environment, a `TRUE` requirement stays `TRUE`, a `FALSE` one stays `FALSE`, and a supported or contradicted decision stays so, aggregates included. |
| `within_tolerance_and_paid_once`, `overpaid_is_contradicted`, `open_listing_is_undetermined`, `two_other_approvers_suffice`, `creator_approval_not_counted` | The worked examples, decided by the model. |

**The hypothesis to read first.** Stability is proved along `Settled`: Language 1's `Extends`, and in addition that a closed kind is **listed as it was**. Language 1's `Extends` already says a closed kind keeps exactly its records. An aggregate also needs the listing to be the same list. That holds when a kind's records are distinct by key and listed in key order, which the specification will require, but the model assumes it rather than proves it (open question 2).

**Not covered by any proof:** the typing rules of arithmetic (units, currencies, `time − time`), the numeric range, the wire form, the work bound, and every implementation. The Scala, JavaScript and Rust implementations are tied to this model by the shared vectors, as they are for Language 1.

## Alternatives

- **Computed fields from the source** (today's workaround). It keeps the language small, but the contract then checks the source's arithmetic claim rather than the arithmetic. It cannot express counts or sums at all.
- **A general expression language** (CEL, Rego, or a subset of JavaScript). More expressive, but evaluation is no longer bounded and three-valued by construction, and the proofs that a contract's meaning is stable would have to be redone for a much larger language. The point of this language is that a decision can be reproduced and reasoned about.
- **Rational numbers and division.** Percentages read more naturally, but every division needs a rounding rule, and rounding rules are where two implementations disagree. Scaling both sides by whole numbers expresses the same tolerances exactly.
- **Counting over open kinds as lower bounds.** `count ≥ n` is monotone even without a completeness statement: n witnesses can only grow. It is attractive for approvals. It is left open, because it makes `count` mean two different things depending on the comparison.

## Open questions

1. **Range.** A result outside (−2⁶³, 2⁶³): a refusal (`ARITHMETIC_RANGE`), or `unknown`? A refusal is honest but lets a large record turn a decision into no decision; `unknown` reads as "the evidence was not enough", which is wrong. The author leans to the refusal.
2. **Settled listings.** Prove, rather than assume, that a closed kind's listing is unchanged along `Extends`, from records being distinct by key and listed in key order. This needs list permutation lemmas that are not in Lean's core library today.
3. **Lower-bound counts** over open kinds for `ge` and `gt` (above).
4. **Durations.** Is `time − time` as an `int` of seconds enough for "within n days", or should `days` be a type?
5. **The package version** that first carries `work-contract-2`, and whether it waits for RFC 0003.

## Decision

Not yet decided.

## Implementation

Not yet implemented. The Lean model is in [`0008/formal`](0008/formal).

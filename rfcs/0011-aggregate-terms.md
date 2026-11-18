# RFC 0011: Aggregates as terms, and products of terms

|            |                                                                                                                                                    |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| RFC        | 0011                                                                                                                                               |
| Status     | Draft                                                                                                                                              |
| Author     | Srishti                                                                                                                                            |
| Created    | 2026-11-18                                                                                                                                         |
| Affects    | Work Contract Language 2 (RFC 0008): an aggregate becomes a term, and a term may be a product (`mul`). RFC 0008's aggregate predicate is unchanged |
| Supersedes | Nothing                                                                                                                                            |

RFC 0008 lets a requirement compare **one** aggregate with a term. Three of the controls procure-to-pay needs most can't be written that way:

- **The amounts add up:** an invoice's net and tax, over its rate groups, equal its gross. That's two sums added.
- **The cumulative three-way match:** what was invoiced against an order, in all, is at most what was received. That's a sum compared with a sum.
- **The tax at the invoice's own rate:** each rate group's tax is its net times its rate, rounded. The rate is a field, and RFC 0008 can only multiply by a constant, so a contract has to list every rate it admits.

This RFC makes an aggregate a term, with RFC 0008's value and the same rule for when it has one, and adds a product of two terms. Everything RFC 0008 decides is decided the same way, and its aggregate predicate is exactly a comparison with an aggregate term.

## Motivation

shadowplay's F007 and S022 wrote F007's German invoice rules (§14(4) UStG, §33 UStDV) as a Language 2 contract and compared it with F007's Lean evaluator on 76,318 invoices. The contract agreed with F007 on every in-scope invoice of F007's grid, but only with two workarounds, both caused by RFC 0008's form:

- **Σ(net + tax) = gross** couldn't be written. The adapter emitted every net and tax a second time, as its own `amount` record, so one `sum` covered both. The same figures then arrive twice, and nothing in the contract checks the two copies agree. That's a gap a wrong adapter can fall through.
- **The rate was listed, not read.** `scale` takes a constant, so the contract had one branch per admitted rate (19, 7, 0 %). On S022's tax set, all 306 invoices at 10 % disagreed, although their tax was right.

The cumulative three-way match is the control shadowplay's F002 baseline proves (`spec_never_overbilled`: nothing invoiced beyond what was received, across all invoices of an order). As a requirement it's `sum(invoiced) ≤ sum(received)`, which RFC 0008 can't state.

Zin noted on RFC 0008 that "aggregates are predicates, not terms, so Σ(net + tax) = gross can't be written directly", and that he'd decide on dekrops/wvp#47 whether this belongs in RFC 0008 before its acceptance or in a follow-up. This RFC is the follow-up, written so that either is possible (Open questions, 1).

## What changes

**An aggregate is a term.** RFC 0008's aggregate form without `cmp` and `than` is a term:

```json
{ "aggregate": "sum", "field": "net", "of": "g", "in": "rateGroup", "where": <predicate> }
{ "aggregate": "count", "of": "a", "in": "approval", "where": <predicate> }
{ "aggregate": "count", "distinct": "approver", "of": "a", "in": "approval", "where": <predicate> }
```

- **Its value** is RFC 0008's: the count or sum, **only when the kind is closed and the body is `TRUE` or `FALSE` for every record**. Otherwise it has no value, like an absent optional field, so any term or comparison that reads it has no value or is `unknown`.
- **Its type** is `int` for `count`, and the summed field's type for `sum`.
- **It may appear wherever a term may:** in `add`, `sub`, `scale`, `abs`, `mul`, either side of a comparison, as `than`, and in another aggregate's body.
- **RFC 0008's aggregate predicate** (the same form with `cmp` and `than`) is kept, and means exactly `{"cmp": cmp, "left": <the aggregate term>, "right": than}`.

**A product of two terms.**

| Form (proposed wire form) | Value       | Static rule                                                                                                               |
| ------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------- |
| `{"mul": [term, term]}`   | the product | at least one operand is an `int`; the result has the other operand's type (`int × money` is money, `int × int` is an int) |

`mul` with an `int` operand is what reading a rate needs: a rate in basis points is an `int`, and `rateBps × net` is money in 1/10,000ths of the net's unit. A contract compares it with `10000 × tax`, as F007's rounding rule does (`10000·(tax − tol) ≤ rateBps·net + 5000 < 10000·(tax + tol + 1)`). Two money operands, or two decimals, can't be multiplied: the result would have no unit the language has.

**Static rules,** in addition to RFC 0008's:

- an aggregate term's variable is bound in its body only, and its nesting counts toward the quantifier depth limit of 3, as RFC 0008's aggregate predicate does;
- each `mul` and each aggregate term counts as a node toward the limit of 512 nodes, and toward _s_ in the work bound;
- `mul`'s operand types follow the table above.

**Range,** as RFC 0008: each `mul` node with a value, and each aggregate term with a value, must lie strictly between −2⁶³ and 2⁶³, or the evaluation refuses `ARITHMETIC_RANGE`. Each node's operands are therefore in range, so a product needs at most 126 bits, and RFC 0008's 128-bit bound holds unchanged.

**What is evaluated,** as RFC 0008: every term is evaluated, including every aggregate term's body for every record, whatever the predicates around it.

## Outcomes that change

- **RFC 0008's contracts: none.** Every Language 2 contract means the same (`extends_language_2`, `same_decision_as_language_2`).
- **New contracts:** the three controls above can be written. Each is `unknown` when a summed kind isn't closed, never `TRUE` or `FALSE` (`agg_open_kind_has_no_value`, `cmp_unknown_of_none`).

## Compatibility

- **If folded into RFC 0008 before it's accepted:** Language 2 is published with these forms, under `work-contract-2`, and nothing else changes.
- **If a follow-up:** a contract using an aggregate term or `mul` is a new language version (RFC 0001, invariant 2), and a verifier that implements only RFC 0008 refuses it as another version (invariant 3). It never misreads it. RFC 0008's contracts are unchanged.
- **Implementations:** verified-cli#61 evaluates aggregates already. An aggregate term reuses that evaluation and returns the value instead of comparing it. `mul` is one more arithmetic node with the same range check.

## Vectors

Proposed, to be generated as RFC 0008's are (`generate.py`), with expectations from the model:

- **The amounts add up:** consistent (`SUPPORTED`), a cent off (`CONTRADICTED`), rate groups not closed (`UNDETERMINED`), and a rate group of another invoice (not counted).
- **The rate read from the group:** 19 %, 7 %, and 10 % with no list of rates (`SUPPORTED`); two cents high (`CONTRADICTED`); a net of 168.03 at 19 %, whose tax is 31.9257 and rounds to 31.93 (`SUPPORTED` at 31.93, `CONTRADICTED` at 31.91).
- **The cumulative three-way match:** within (`SUPPORTED`), one unit beyond (`CONTRADICTED`), receipts not closed (`UNDETERMINED`).
- **Refusals:** `mul` of two money operands (`CONTRACT_ILL_FORMED`); a product out of range (`ARITHMETIC_RANGE`); an aggregate term whose sum is out of range (`ARITHMETIC_RANGE`); an aggregate term nested beyond depth 3 (`CONTRACT_ILL_FORMED`).
- **RFC 0008's predicate and the term form** give the same result on every RFC 0008 aggregate vector.

## Security considerations

This changes what a verified result may be relied on for, so it needs security review (RFC 0001, section 9.1).

- **Nothing new is trusted.** An aggregate term rests on the same completeness statements as RFC 0008's aggregate predicate, and `mul` computes from accepted values only.
- **It removes a workaround that was a risk.** Without aggregate terms, Σ(net + tax) = gross needed the adapter to emit every amount twice, and nothing checked the copies agreed. With them, the contract reads each amount once.
- **Comparing two aggregates rests on two completeness statements.** `sum(invoiced) ≤ sum(received)` is decided only when both kinds are closed. A source that declares receipts complete when they aren't can make a three-way match pass. That's the trust RFC 0008 already places in each completeness statement, now combined.
- **Range and refusals** are as RFC 0008: a source can force `ARITHMETIC_RANGE`, never a different decision.

## Formal semantics

`0011/formal` extends RFC 0008's model (`rfcs/0008/formal`) with mutual `Term` and `Pred`, in Lean 4.24 with no Mathlib. `check.sh` audits 19 theorems: no `sorry`, only `propext`, `Classical.choice` and `Quot.sound`.

| Theorem                                       | Statement                                                                                                                  |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `extends_language_2`                          | Every RFC 0008 requirement has the same value here, in every environment and scope                                         |
| `same_decision_as_language_2`                 | An RFC 0008 contract has the same decision                                                                                 |
| `agg_is_cmp`                                  | RFC 0008's aggregate predicate is exactly a comparison with the aggregate term                                             |
| `agg_value_requires_closed`                   | An aggregate term with a value was taken over a closed kind, every body settled                                            |
| `agg_open_kind_has_no_value`                  | Over a kind no source declared complete, an aggregate term has no value                                                    |
| `cmp_unknown_of_none`, `add_none`, `mul_none` | A comparison or arithmetic reading a term with no value is unknown or has none                                             |
| examples                                      | The three controls of the Motivation, decided: each `SUPPORTED`, `CONTRADICTED` and `UNDETERMINED` case above, by `decide` |

**Not proved:**

- **Stability:** RFC 0008's `eval_monotone` and `definite_decision_is_stable` restated for the extended language, along `Settled`. Its argument should carry over, since an aggregate term's value is RFC 0008's `Aggregate.value` (proved order-independent by `value_perm`), but it isn't done.
- **The typing and range,** as in RFC 0008.

The stability theorems are needed before this RFC asks for Review.

## Alternatives

- **Keep the workarounds.** Emitting every amount twice and listing every rate works for one jurisdiction's rates, and leaves the copies unchecked.
- **A dedicated "sum of a term over records"** (`sum(net + tax)` per record) instead of adding two sums. It covers Σ(net + tax) = gross but not the three-way match (two different kinds), and adds a second sum form. An aggregate term covers both. Summing a term per record may still be worth adding later (Open questions, 2).
- **Division,** to read a rate as a fraction. It would bring rounding into the language, which RFC 0008 kept out. Basis points and `mul` express every rounding rule seen so far, as exact integer comparisons.

## Open questions

1. **Fold into RFC 0008, or follow-up?** Zin decides on #47. Folding restarts RFC 0008's review period (RFC 0001, section 5, rule 2); a follow-up needs a new language version.
2. **Summing a term per record** (`"sum": <term>` instead of `"field"`). It isn't needed for any control seen so far.
3. **With RFC 0009 (`kleene-2`).** An interval composes with `add`, `sub`, `scale` and `mul` by interval arithmetic, so the two RFCs work together. Stating that is RFC 0009's open question 1, and it's left to whichever is accepted second.

## Decision

Not yet decided.

## Implementation

Not yet implemented. The model is in `0011/formal`. In verified-cli, an aggregate term reuses #61's aggregate evaluation, and `mul` is one more arithmetic node.

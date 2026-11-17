# RFC 0009: Interval aggregates: deciding what the evidence already settles

|            |                                                                                                       |
| ---------- | ----------------------------------------------------------------------------------------------------- |
| RFC        | 0009                                                                                                  |
| Status     | Draft                                                                                                 |
| Author     | Srishti                                                                                               |
| Created    | 2026-11-17                                                                                            |
| Affects    | `work-contract-2` (RFC 0008): a new evaluation semantics `kleene-2`, and a field declaration `nonNegative`. `kleene-1` is unchanged |
| Supersedes | Nothing                                                                                               |

RFC 0008 gives `count` and `sum` a value only over a closed kind with every body settled; otherwise the comparison is `unknown`. That is sound, but it leaves `unknown` many comparisons the evidence already settles. A sum of payments, all of them seen and some perhaps reversed, can be within the bound whatever the missing reversals say. Payments already seen can exceed the bound whatever is still missing. This RFC proposes evaluation semantics `kleene-2` for Language 2:
- an aggregate is evaluated as the **interval** of values it can still take, and a comparison is decided when the whole interval is on one side of it;
- a numeric field may be declared `nonNegative`, so that a kind nobody declared complete still has a lower bound.

Where RFC 0008 has a value, the interval is that value, so nothing it decides changes. Everything `kleene-2` decides is what any settled extension of the evidence would decide. RFC 0008's open question 1 (lower-bound counts over open kinds) is answered as a special case.

## Motivation

**Origin.** The idea is Zin Nam's. His F007 comment on RFC 0008 ([dekrops/wvp#47](https://github.com/dekrops/wvp/pull/47#issuecomment-6910878602), section 2, 2026-11-16) proposed a polarity-aware variant: a `sum` of non-negative amounts over an open kind is a lower bound, and it may settle a requirement only where a lower bound suffices. He also pre-registered measuring its cost: shadowplay S021, part B, over F007's 9,768 honest observations. This RFC states that idea as a semantics, with both bounds, as an interval, and with `count` and `distinct`. It proves its core properties, and reports one exploratory measurement below. S021 remains the pre-registered measurement.

The F007 study (shadowplay, `studies/F007-invoice-to-payment-landscape`) has a machine-checked verdict on payments, `Landscape.evaluate`. It is proved sound (`T5_env`) and asymmetric in what it needs:
- `pass` (paid within the approval) needs the settlements complete, not the reversals, because a missing reversal can only make the payment look larger;
- `fail` needs the reversals and approvals complete, not the settlements, because settlements already seen can only grow.

In an exploratory run (not pre-registered, on a sweep of my own, not S021's population), that verdict was written as one WCL2 requirement: `or(net ≤ 0, exists a: net ≤ a.gross)`, with `net` the `sum` of settlements up to the cutoff whose reversal wasn't seen. Both evaluators were run on the same environments: verified-cli's WCL2 implementation (dekrops/verified-cli#61) and F007's Lean `evaluate`. That's a system result, one run, 2026-11-17. The contracts, environments and scripts will be published with the F007 study in shadowplay.

| Observations | Agree | F007 decides, WCL2 `UNDETERMINED` | Opposite verdicts |
| --- | --- | --- | --- |
| F007's 8 fixture cases | 8 | 0 | 0 |
| 2,048-observation sweep (every combination of seen settlements and reversals, completeness per kind, approvals seen) | 1,794 | **254** | 0 |

Every one of the 254 is one of two patterns:

| Listings complete | Count | F007 | Why it can decide |
| --- | --- | --- | --- |
| settlements yes, **reversals no** | 212 | `pass` | the missing reversals could only lower the net |
| **settlements no**, reversals and approvals yes | 42 | `fail` | the settlements seen already exceed the bound |

These are not edge cases. "The bank statement is closed but the reversal feed lags" and "we haven't got the full payment run yet but already see too much" are the normal states of an AP process. A verifier that says `UNDETERMINED` in them is right, but not useful, and the contract author can't fix it in RFC 0008's language.

The same gap appears for approvals. "At least two approvers" over an approval listing nobody declared complete is settled by two witnesses (RFC 0008, open question 1).

## What changes

**A new evaluation semantics, `kleene-2`, for `work-contract-2`.** A contract declares it in `evaluation.semantics`, as it declares `kleene-1` today. Everything except aggregates is evaluated as under `kleene-1`.

**An aggregate's interval.** For an aggregate over kind *K* with body *B*, each record *r* of *K* that step 5 keeps has a body value *b(r)* ∈ {TRUE, FALSE, unknown} and, for `sum`, a field value *v(r)*. `count` is `sum` with *v(r)* = 1.

| | over a closed kind | over an open kind |
| --- | --- | --- |
| **lo** | Σ *v(r)* over TRUE, plus Σ min(*v(r)*, 0) over unknown | the same, if the field is declared `nonNegative`; otherwise −∞ |
| **hi** | Σ *v(r)* over TRUE, plus Σ max(*v(r)*, 0) over unknown | +∞ |

For `count` with `distinct`:
- **lo** is the number of distinct values over the TRUE records;
- **hi** is the number of distinct values over the TRUE and unknown records, or +∞ over an open kind.

**A comparison with an interval.** `[lo, hi] op x` is TRUE if every value in the interval satisfies `op x`, FALSE if none does, and unknown otherwise. For example:
- `le`: TRUE iff hi ≤ x; FALSE iff lo > x;
- `eq`: TRUE iff lo = hi = x; FALSE iff x < lo or x > hi.

A `than` without a value makes the comparison unknown, as now.

**`nonNegative`.** A field of a numeric type may carry `"nonNegative": true`.
- An accepted fact whose value for it is negative doesn't conform (`ENVIRONMENT_NONCONFORMING`, step 3).
- Under `kleene-2`, it gives a `sum` over an open kind a finite lower bound.
- `count` is non-negative by construction.

**Range.** Each finite bound must lie strictly between −2⁶³ and 2⁶³, or the evaluation refuses (`ARITHMETIC_RANGE`), as RFC 0008 checks an aggregate's value. An infinite bound computes nothing and isn't checked. Partial totals aren't checked.

**Everything is still evaluated.** RFC 0008's "every term is evaluated" is unchanged. The interval reads the same body values and field values RFC 0008 already computes.

## Outcomes that change

- **Under `kleene-1`: none.** Language 2 with `kleene-1`, and its proposed vectors, are untouched.
- **Under `kleene-2`, compared with `kleene-1` on the same contract and environment:**
  - every TRUE and FALSE stays the same (`cmp_agrees`, `contains_settled`);
  - some unknowns become TRUE or FALSE, exactly where the interval lies on one side;
  - a contract may refuse `ARITHMETIC_RANGE` where `kleene-1` said unknown, if a bound it now computes is out of range (see Security considerations).
- A contract moved from `kleene-1` to `kleene-2` is a new contract, with a new digest, signed again.

## Compatibility

- **Producers** keep `kleene-1` until they want the stronger verdicts. A contract that wants open-kind lower bounds also declares `nonNegative` on the summed fields, and keeps negative amounts (refunds, credit notes) in a kind of their own.
- **Verifiers** that implement only `kleene-1` refuse a `kleene-2` contract (`CONTRACT_ILL_FORMED`, static rule 1, as for an unknown semantics). They never misread it.
- **Relying parties:**
  - `SUPPORTED`, `CONTRADICTED` and `UNDETERMINED` keep their meaning;
  - `UNDETERMINED` still means the evidence wasn't enough;
  - it now means that in fewer cases.
- **Packages:** as for Language 2, a package carrying `kleene-2` is a new package version (RFC 0001, invariant 2).

## Vectors

- **Every Language 2 case, restated under `kleene-2`, with its expectation.**
  - A case is unchanged unless the interval decides it.
  - The cases that change are listed with the reason: an aggregate over a closed kind with an unknown body whose sign split decides; an open kind with `nonNegative`.
  - RFC 0008's proposed vectors declare no `nonNegative` field, so open-kind cases 224, 231, 243 and 249 stay unknown.
- **New cases:**
  - an open `nonNegative` sum exceeding the bound (FALSE);
  - an open sum without `nonNegative` (unknown);
  - a closed sum with unknown bodies of both signs;
  - `count ≥ n` over an open kind with n witnesses (TRUE) and with n − 1 (unknown);
  - `distinct` over an open kind;
  - `eq` and `ne` at the interval's ends;
  - a negative value in a `nonNegative` field (`ENVIRONMENT_NONCONFORMING`);
  - a finite bound out of range (`ARITHMETIC_RANGE`);
  - an infinite one (not checked).
- **A differential set with an independent oracle:** F007's 2,048-observation sweep, with expectations from F007's proved `Landscape.evaluate`, not from this RFC's model. Under `kleene-2` all 2,048 are expected to agree (checked against a Python model of this RFC, published with the F007 cross-check).

## Security considerations

This changes what a verified result may be relied on for, so it needs security review (RFC 0001, section 9.1).

- **What a decision rests on.** A `kleene-2` decision rests on three things:
  - the records seen;
  - the completeness statements, as under `kleene-1`;
  - for open kinds, the contract's `nonNegative` declaration.

  The declaration is the contract author's claim that no record of that field is negative. It is enforced on every record seen (a negative one doesn't conform), never on records not seen. A source that hides a negative record isn't detected until it delivers one, but that's also a source hiding a record, which `kleene-1` already trusts it not to do once it declares the kind complete.
- **No decision from absence.** An open kind still never gives an upper bound, and without `nonNegative` it gives no lower bound either. Missing evidence still never becomes `SUPPORTED`.
- **Stability.** Under the model's hypotheses (records only added to open kinds, closed kinds closed, bodies only settling, as RFC 0008's `eval_monotone` gives), lo never falls and hi never rises. A TRUE or FALSE comparison stays so. See Formal semantics.
- **A refusal from more evidence.** As under RFC 0008, a source accepted for a kind can push a computed bound out of range and force `ARITHMETIC_RANGE` where the evaluation decided before. It can force a refusal, never a different decision.
- **Counting records, not people.** It's unchanged: a lower-bound count over open approvals counts records. Four eyes uses `distinct`, whose lower bound counts distinct values seen.

## Formal semantics

`0009/formal/Interval.lean` is a standalone model, in Lean 4.24's core only, at the level of one aggregate: a list of (body value, field value) pairs. The axioms used are `propext`, `Quot.sound` and `Classical.choice`, within `formal/lean/check.sh`'s rules. There is no `sorry`.

| Theorem | Statement |
| --- | --- |
| `agrees_when_settled` | Where RFC 0008's `sum`/`count` has a value, lo = hi = that value |
| `cmp_agrees` | Comparing that single value is RFC 0008's comparison |
| `lo_narrows`, `hi_narrows` | Along more evidence (bodies refined, records added only to an open kind, closed stays closed, `nonNegative` fields conform), lo never falls and hi never rises |
| `contains_settled` | The value over any settled extension lies in [lo, hi] |
| `bounds_nonempty` | lo ≤ hi |
| `cmp_stable` | A TRUE or FALSE interval comparison stays so along more evidence |
| examples | The two F007 patterns of the Motivation, decided; the open kind without `nonNegative`, unknown |

**Not proved:**
- the integration into RFC 0008's full model (`Pred.eval`, scopes, `Settled`, reordering), meaning `eval_monotone` and `definite_decision_is_stable` restated for `kleene-2`;
- `distinct`'s interval;
- typing and range.

These are needed before this RFC asks for Review. The model's `Refines` keeps records in order; RFC 0008's `value_perm` argument should carry over, but that isn't done.

**Tested:** the Python model agrees with F007's evaluator on 2,048 of 2,048 observations. No implementation exists yet.

## Alternatives

- **Write the asymmetry into each contract.** For `pass`, ignore reversals: `sum(all settlements) ≤ bound`. It recovers some `pass` cases, but not those where a seen reversal matters, and no `fail` case: the sum over an open kind has no value. Each contract would also have to get it right.
- **Polarity only, as first proposed on #47:** a lower bound, used where its position in the comparison makes a lower bound sufficient. The interval gives the same verdicts where a lower bound suffices, and also covers upper bounds from closed kinds with unknown bodies, and `count`, without a separate polarity analysis of the predicate.
- **Lower-bound `count` only** (RFC 0008, open question 1). It solves four eyes, but not sums, and makes `count` mean two things depending on the comparison. Here `count` keeps one meaning (a number), and the comparison decides what it can.
- **Fold this into RFC 0008 before it's accepted.** Language 2 would then have one semantics from the start. But RFC 0008 is in Review, and this is a change of substance (RFC 0001, section 5, rule 2): its review period would restart, and its arithmetic, which F007 and the product need now, would wait. See Open questions.
- **Unknown-as-zero for missing records.** It's unsound: that is exactly F007's planted weakness C-W6 (the verifier reads absence as "none").

## Open questions

1. **A semantics identifier (`kleene-2`) or a fold into RFC 0008?** This draft takes the identifier, so RFC 0008 can be accepted on schedule. Folding is cleaner if Language 2 isn't published before this is decided.
2. **`nonNegative` or a general lower bound per field** (`"min": "<number>"`)? `nonNegative` covers every case seen so far.
3. **Should `abs` and `sub` of intervals be defined, so that aggregates can appear inside terms?** That's the separate G1 question (aggregates as terms). It would compose with this one, but isn't proposed here.

## Decision

Not yet decided.

## Implementation

Not yet implemented. The model is in `0009/formal`. The F007 cross-check that motivates it is to be published with the study in shadowplay.

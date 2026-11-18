# RFC 0012: When a requirement applies

|            |                                                                                                                                      |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| RFC        | 0012                                                                                                                                 |
| Status     | Draft                                                                                                                                |
| Author     | Srishti                                                                                                                              |
| Created    | 2026-11-18                                                                                                                           |
| Affects    | Work Contract Language 2 (RFC 0008): a requirement may say when it applies, and a requirement and a decision may be `NOT_APPLICABLE` |
| Supersedes | Nothing                                                                                                                              |

A requirement today either holds, fails or is unknown. Many rules hold only in some cases: the tax check applies to an invoice that isn't under reverse charge, and a three-way match applies to an order for goods, not for services. Written today, a case the rule doesn't apply to has to come out `FALSE`, so the contract is `CONTRADICTED`, the same as a real failure.

This RFC lets a requirement carry a condition, `appliesWhen`. Where the condition is `FALSE`, the requirement is `NOT_APPLICABLE`: it neither holds nor fails. A contract none of whose requirements applies is `NOT_APPLICABLE`. A contract without conditions is decided exactly as today.

## Motivation

shadowplay's S022 wrote F007's German invoice rules (§14(4) UStG, §33 UStDV) as one Language 2 contract. F007 sorts each invoice into `pass`, `fail` or `review`, where `review` is an invoice the rules don't cover: reverse charge (§13b UStG) and supplies before 2025. The contract had only `TRUE`, `FALSE` and `unknown` to say this with, so all 46,080 `review` invoices came out `CONTRADICTED`. Of them, 3,966 met every invoice rule on F007's grid (11,772 on grid-round). A reader of the result couldn't tell them from the invoices that broke a rule.

The same shape comes up across procure-to-pay:

- **Tax:** the rate check applies to domestic invoices; reverse charge and intra-EU supplies follow other rules.
- **Three-way match:** it applies to goods; services have no goods receipt.
- **Approvals:** a second approver applies above a threshold.

Each can be written today by putting the condition inside the predicate (`not(condition) or rule`), but then a case outside the rule comes out `TRUE`, which reads as "checked and fine" when nothing was checked.

## What changes

**A requirement may say when it applies.** Next to `id` and `predicate`, a requirement may carry `appliesWhen`, a predicate of the same language:

```json
{
  "id": "TAX_AT_19",
  "appliesWhen": <predicate: the invoice is not under reverse charge>,
  "predicate": <predicate: the tax is 19 % of the net>
}
```

`appliesWhen` follows the static rules of a requirement's `predicate`: it's evaluated with nothing bound, and its nodes count toward the node limit and the work bound.

**A requirement's value.**

| `appliesWhen` | The requirement's value         |
| ------------- | ------------------------------- |
| absent        | the predicate's value, as today |
| `TRUE`        | the predicate's value           |
| `FALSE`       | `NOT_APPLICABLE`                |
| unknown       | unknown: it may yet apply       |

**The decision,** in this order:

1. `CONTRADICTED` if any requirement is `FALSE`;
2. otherwise `UNDETERMINED` if any is unknown;
3. otherwise `NOT_APPLICABLE` if the contract has a requirement and every one is `NOT_APPLICABLE`;
4. otherwise `SUPPORTED`.

Without step 3 and the `NOT_APPLICABLE` value, this is Language 1's rule (section 7, step 8). A requirement that doesn't apply is left out of the decision, so a contract where some requirements apply and hold, and the rest don't apply, is `SUPPORTED`.

**What is evaluated,** as RFC 0008: every term is evaluated, `appliesWhen` and `predicate` both, whatever the condition's value. A requirement that doesn't apply still refuses `ARITHMETIC_RANGE` if a term in it is out of range.

**The result** names `NOT_APPLICABLE` as a requirement value and as a decision, alongside `TRUE`, `FALSE`, `UNKNOWN` and `SUPPORTED`, `CONTRADICTED`, `UNDETERMINED`.

## Outcomes that change

- **Contracts without `appliesWhen`: none.** They're decided as before (`without_conditions`).
- **New contracts:** a case a rule doesn't apply to is `NOT_APPLICABLE`, not `CONTRADICTED`. The examples in `0012/formal` show the reverse-charge invoice both ways: `CONTRADICTED` without the condition, `SUPPORTED` with it (`reverse_charge_without_condition`, `reverse_charge`).

## Compatibility

- **A new form and a new outcome.** A contract with `appliesWhen` is a new language version (RFC 0001, invariant 2), or part of Language 2 if folded into RFC 0008 before it's accepted, as RFC 0011 may be. A verifier that doesn't implement it refuses the contract as another version (invariant 3). It never reads a requirement without its condition.
- **Relying parties.** A system that consumes decisions must handle `NOT_APPLICABLE`. It must not read it as `SUPPORTED`: nothing was checked.
- **Implementations:** in verified-cli, `appliesWhen` is one more predicate per requirement, and the decision step gains one case.

## Vectors

`0012/generate.py` writes them to `0012/vectors/work-contract/v2`, built on RFC 0008's generator. For each of the 12 with a result, `formal/Applies/Vectors.lean` proves by `decide` that the model gives exactly the expected requirement values and decision. The 3 refusals rest on this RFC's text.

- **A domestic invoice** (`400`, `401`): the tax check applies and holds (`SUPPORTED`), applies and fails (`CONTRADICTED`).
- **Reverse charge** (`402`, `403`): the tax check doesn't apply and the gross check holds (`SUPPORTED`, the tax check `NOT_APPLICABLE`); the same without `appliesWhen` (`CONTRADICTED`).
- **Nothing applies** (`404`): the contract's only requirement doesn't apply (`NOT_APPLICABLE`).
- **The condition unknown** (`405`, `407`): the invoice not yet seen, in a listing not declared complete; and `reverseCharge` not recorded, though the tax is right (`UNDETERMINED` both).
- **A failure where the rule doesn't apply** (`406`): reverse charge with a tax shown, which the tax check would reject (`SUPPORTED`, the tax check `NOT_APPLICABLE`).
- **A second invoice** (`408`–`411`): the invoice asked about right and another wrong (`SUPPORTED`), the reverse (`CONTRADICTED`), and the same for the condition: this invoice under reverse charge and another domestic (`NOT_APPLICABLE`), and the reverse (`SUPPORTED`). These check that both `appliesWhen` and `predicate` read the invoice asked about, and only it (shadowplay S023).
- **Refusals** (`420`–`422`): `appliesWhen` that isn't a predicate (`CONTRACT_MALFORMED`); `appliesWhen` reading a variable it doesn't bind (`CONTRACT_ILL_FORMED`); a term out of range in a requirement that doesn't apply (`ARITHMETIC_RANGE`).

## Security considerations

This changes what a verified result may be relied on for, so it needs security review (RFC 0001, section 9.1).

- **A condition can switch a check off, and it reads evidence.** Whoever supplies the facts a condition reads can make a requirement not apply. If an invoice's own `reverseCharge` flag decides whether its tax is checked, a seller who sets the flag skips the tax check. Two mitigations, both the contract author's:
  - accept the facts a condition reads only from sources trusted for them, as for any other fact (`evidence.sources`);
  - pair the condition with a requirement for the other case. Reverse charge, for example, needs the buyer's VAT ID and the note "Steuerschuldnerschaft des Leistungsempfängers" (§14a(5) UStG), so that a reverse-charge invoice is checked too, by another rule.
- **`NOT_APPLICABLE` is not `SUPPORTED`.** A contract that is `NOT_APPLICABLE` says nothing about the case. A relying party that treats it as a pass has checked nothing.
- **Stability is kept.** `NOT_APPLICABLE` is settled like `TRUE` and `FALSE`: more evidence never changes it (`result_kept`, `decision_is_stable`).
- **Range and refusals** are as RFC 0008: every term is evaluated, so a condition can't hide a term that should refuse.

## Formal semantics

`0012/formal` is a model in Lean 4.24 with no Mathlib. It's generic in the predicate language: `eval` is any evaluation of a predicate to a `Truth`. The stability theorem needs only that `eval` is stable along more evidence, which RFC 0008 (`eval_monotone`), RFC 0011 and RFC 0009 (`kleene-2`) each prove. So it holds with any of them. Language 2 is the instance the examples use. `check.sh` audits 27 theorems, 12 of them the vectors: no `sorry`, only `propext`, `Classical.choice` and `Quot.sound`.

| Theorem                         | Statement                                                                                                                                          |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `without_conditions`            | A contract with no `appliesWhen` is decided exactly as Language 1 decides it                                                                       |
| `notApplicable_iff`             | A requirement is `NOT_APPLICABLE` exactly when it has a condition and the condition is `FALSE`                                                     |
| `false_only_where_it_applies`   | A requirement is `FALSE` only where its condition, if any, is `TRUE`: a requirement that doesn't apply never makes a contract `CONTRADICTED`       |
| `outcome_notApplicable_iff`     | A contract is `NOT_APPLICABLE` exactly when it has a requirement and none applies                                                                  |
| `result_kept`                   | A requirement that is `TRUE`, `FALSE` or `NOT_APPLICABLE` stays so along more evidence, for any stable predicate language                          |
| `decision_is_stable`            | A decision that is `SUPPORTED`, `CONTRADICTED` or `NOT_APPLICABLE` stays so along more evidence, for any stable predicate language                 |
| `language_2_decision_is_stable` | The same, for RFC 0008's Language 2 along `Settled`                                                                                                |
| examples                        | Decided by `decide`: domestic (`SUPPORTED`, `CONTRADICTED`), reverse charge with and without the condition, nothing applies, the condition unknown |

**Not proved:** the typing and range, as in RFC 0008.

## Alternatives

- **Put the condition inside the predicate** (`not(condition) or rule`). It needs no change, but a case outside the rule is `TRUE`, which reads as "checked and fine".
- **Refuse the claim instead.** Verified could refuse a claim for a case the contract doesn't cover, before evaluating (`CLAIM_…`), and keep three outcomes. It works for a whole contract, but not for one requirement out of several, which is the common case (the tax check doesn't apply, the gross check does). It also moves evidence-dependent reasoning into the claim, which is meant to say only what is claimed.
- **One condition for the whole contract** instead of one per requirement. It covers S022's `review` invoices, but not a contract where different rules cover different cases. A contract-level condition is the same condition on every requirement.

## Open questions

1. **Fold into RFC 0008, or follow-up?** As for RFC 0011: folding restarts RFC 0008's review period (RFC 0001, section 5, rule 2); a follow-up needs a new language version.
2. **A contract where nothing applies:** `NOT_APPLICABLE` as proposed, or `UNDETERMINED`? `NOT_APPLICABLE` is settled and says why; `UNDETERMINED` would avoid a fourth decision, but would claim the contract might still be decided, which it can't.
3. **Should a result say which requirements didn't apply?** It already lists each requirement's value, so `NOT_APPLICABLE` appears there. Nothing more seems needed.

## Decision

Not yet decided.

## Implementation

Not yet implemented. The model is in `0012/formal`.

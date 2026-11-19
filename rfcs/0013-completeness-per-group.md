# RFC 0013: Completeness per group

|            |                                                                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| RFC        | 0013                                                                                                                                         |
| Status     | Draft                                                                                                                                        |
| Author     | Srishti                                                                                                                                      |
| Created    | 2026-11-19                                                                                                                                   |
| Affects    | Work Contract Language 2 (RFC 0008, with RFC 0011): a completeness statement may cover groups of a kind, and a quantifier may read one group |
| Supersedes | Nothing                                                                                                                                      |

Today a completeness statement covers a whole kind: "these are all the payments". If one payment record can't be read, the kind isn't complete, and every check over payments is `UNDETERMINED`, for every invoice, although the lost record belongs to one of them.

This RFC lets a completeness statement cover **groups** of a kind: "these are all the payments, for every invoice except INV-02". And it lets a quantifier or aggregate read **one group**: "the payments of this invoice". Such a quantifier is closed when its group is, so a record lost from one group leaves only that group's checks undecided. A contract that doesn't use groups is decided exactly as today.

## Motivation

An adapter that maps ERP exports to records, written for a pilot, never guesses. A row it can't read is rejected, and its export is no longer stated complete. On a synthetic month of 14 invoices with four bad rows (a currency out of scope, a fraction of a unit, a typo in an amount, an ID reused with another value), **70 of the 98 results became "can't be decided yet"**:

| Bad row                                 | Results it made undecidable |
| --------------------------------------- | --------------------------: |
| An invoice in US dollars                |                          30 |
| A quantity of 2,5                       |                          26 |
| A payment amount with a letter O        |                          14 |
| An approval ID reused, different amount |                           5 |

Each bad row belongs to one invoice, one order or one supplier, and the adapter can read which: only the amount or the currency was wrong. But a completeness statement can't say "complete except for that invoice", so one row takes a whole kind out, and every check that reads the kind with it. In a real month with thousands of invoices, one bad row would leave a whole control undecided.

With this RFC, the same month has **at most 4 results undecided**: exactly the checks of the invoices the bad rows belong to. This was measured by simulating the change with today's verified-cli, one invoice at a time (outside this repository). No result becomes a pass or a failure it wasn't with the clean exports.

## What changes

**1. A completeness statement may cover groups.** Next to `kind`, `source` and `asOf`, a statement may carry `per`, a field of the kind, and exactly one of `only` or `except`, a list of values of that field:

```json
{
  "kind": "payment",
  "source": "erp",
  "asOf": "1775001600",
  "per": "invoice",
  "except": ["INV-02"]
}
```

It says: for every value of `invoice` except `INV-02`, the environment holds every payment with that value. With `only`, the statement covers the listed values and no other. A statement with `per` covers groups only; it doesn't close the kind. `per` must name a field the kind declares as required, and the values must fit its type.

A group is **closed** when a statement from a source accepted for the kind covers it, with `asOf` not earlier than the cutoff, as for a kind (Language 1, section 7, step 6). A kind with an unsettled conflict is open, and so is every group of it.

**2. A quantifier or aggregate may read one group.** `exists`, `forall` and every aggregate may carry `per`: a field of the kind, and a term for its value.

```json
{ "aggregate": "sum", "field": "amount", "in": "payment", "of": "p",
  "per": { "field": "invoice", "is": { "input": "invoice" } },
  "where": <predicate> }
```

It ranges over the records of the kind whose `field` equals the term's value, and only those. It's closed when the kind is closed or its group is. The term is evaluated where the quantifier is, before `p` is bound, so it can't read `p`. If the term has no value, the group is unknown: an `exists` or `forall` is `unknown`, and an aggregate has no value.

Without `per`, a quantifier is as today. A `where` may still test the same field; it's then redundant but harmless.

**3. Evaluation,** in Language 1's section 7, step 7: `exists` and `forall` read "_K_ is not closed" as "the listing is not closed", where the listing is the kind, or with `per`, the group. An aggregate has a value only when its listing is closed and every body is settled (RFC 0008).

## Outcomes that change

- **Contracts without `per`: none,** whatever statements an environment carries (`same_decision_without_per`). A statement with `per` never closes a kind.
- **Contracts with `per`:** a check over a closed group is decided where it was `UNDETERMINED` before. The examples in `0013/formal` show the same payment check both ways: `UNDETERMINED` with today's quantifier, `SUPPORTED` with `per` (`paid_within_approval_today`, `paid_within_approval_decided`).

## Compatibility

- **A new form, in the contract and in the environment.** A contract with `per` is a new language version (RFC 0001, invariant 2), or part of Language 2 if folded into RFC 0008 before it's accepted. A verifier that doesn't implement it refuses the contract as another version (invariant 3).
- **Environments:** a statement with `per` is new. A verifier that doesn't know it must refuse the environment rather than read it as a statement for the whole kind, which would claim more than the source did. `complete` is ordered by (`kind`, `source`, `per`), a statement without `per` first.
- **Admission and adapters:** a source or adapter states a group complete only when it holds every record of it. An adapter would state "except" the groups its rejected rows fall in, and no group at all when a rejected row's group field can't be read.
- **verified-cli:** `per` is one more filter on a quantifier's listing, and the closed check gains one lookup.

## Vectors

To be generated with an implementation, from the examples in `0013/formal/WCL2G/Examples.lean`, each proved by `decide`:

- **Decided with `per`** (`paid_within_approval_decided`): the invoice's payments are complete as a group; they add up within the approval (`SUPPORTED`).
- **Today's form** (`paid_within_approval_today`): the same environment, without `per` (`UNDETERMINED`).
- **The group with the bad row** (`other_invoice_undecided`, `except_leaves_its_exception`): its group isn't covered (`UNDETERMINED`).
- **Failures still caught** (`overpaid_caught`): an overpayment in a complete group (`CONTRADICTED`).
- **Missing evidence found** (`missing_approval_found`, `missing_approval_today`): no approval in a complete group (`FALSE`), where today's form is `UNKNOWN`.
- **"Every invoice except"** (`except_decides_others`): decides the other invoices, including one with no payments at all.
- **Exactness** (`group_is_exact`, `group_is_per_kind`, `no_key_is_unknown`): a group names one value, of one kind; with no key, nothing is closed.
- **Refusals,** to be written: `per` on an optional or undeclared field; `per` whose term reads the quantifier's own variable; a statement with both `only` and `except`, or neither.

## Security considerations

This changes what a verified result may be relied on for, so it needs security review (RFC 0001, section 9.1).

- **A group statement is a completeness statement.** It carries the same trust: a source that states a group complete when it isn't can make a sum too small or a check pass. Who may state which kind complete remains the relying party's registry (invariant 7). An `except` statement claims more than an `only` one, and should be read with that in mind.
- **The group field decides where a record counts.** A payment recorded against the wrong invoice falls outside its invoice's group, and a check of that invoice doesn't see it. That's no different from today, where `where` filters by the same field, but a group statement now rests on it. The field should come from a source trusted for it.
- **Stability is kept.** Along more evidence that adds no record to a closed kind or a closed group, a requirement that is `TRUE` or `FALSE` stays so, and so does a `SUPPORTED` or `CONTRADICTED` decision (`eval_monotone`, `definite_decision_is_stable`).
- **Fail closed.** A quantifier over a group is `FALSE` (`exists`) or `TRUE` (`forall`), and an aggregate has a value, only when the kind or exactly that group was stated complete (`ex_false_requires_closed_group`, `all_true_requires_closed_group`, `agg_value_requires_closed_group`).

## Formal semantics

`0013/formal` is a model in Lean 4.24, with no Mathlib, built on RFC 0011's model (aggregates as terms), which builds on RFC 0008's and Language 1's. The environment gains `groups kind field value`; `exists`, `forall` and aggregates gain an optional group field and a key term. `check.sh` audits 34 theorems: no `sorry`, only `propext`, `Classical.choice` and `Quot.sound`.

| Theorem                                                               | Statement                                                                                                                             |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `pred_ofT_eval`, `same_decision_without_per`                          | Every RFC 0011 contract means the same here, whatever groups are declared                                                             |
| `listing_closed_iff`                                                  | A listing is closed only if its kind is, or it reads one group and exactly that group was declared                                    |
| `mem_group_listing`                                                   | A group holds the records of the kind with that value in the field, and only them                                                     |
| `ex_false_requires_closed_group` and the `forall` and aggregate forms | Fail closed: "there is none", "all of them" and an aggregate's value need the kind or that group closed                               |
| `listing_kept`                                                        | Along more evidence, no record leaves a listing, and a closed listing stays closed with no record added, for a kind and a group alike |
| `term_kept`, `pred_kept`, `eval_monotone`                             | A term with a value keeps it; a requirement that is `TRUE` or `FALSE` stays so                                                        |
| `definite_decision_is_stable`                                         | A `SUPPORTED` or `CONTRADICTED` decision stays so                                                                                     |
| examples                                                              | 11 examples by `decide`, listed under Vectors                                                                                         |

**Not proved:** the typing (that `per` names a required field, and its term can't read the quantifier's variable) and the wire form, as in RFC 0008. The measurement under Motivation is a simulation, not a proof.

## Alternatives

- **One environment per invoice,** each with its own whole-kind statements, decided by the adapter. It needs no language change, and works today. But whether a kind is complete "for this invoice" then depends on which groups the contract happens to read, worked out outside the verifier, so a mistake there is a wrong `SUPPORTED` that nothing checks. This RFC puts the same reasoning in the language, where it's proved.
- **Detect the group from `where`** (a first conjunct `p.invoice = …`) instead of writing `per`. It needs no new form in the contract, but makes the meaning of a quantifier depend on how its body is written, and a reordered `and` would change a result.
- **Lower-bound counts** (RFC 0008's open question 1) help `count ≥ n` over open kinds, but not sums, `forall`, or "there is none".

## Open questions

1. **Fold into RFC 0008, or follow-up?** As for RFC 0011 and 0012.
2. **Conflicts:** should an unsettled conflict open only the groups the conflicting records fall in, rather than the whole kind? It would be finer, and would need its own stability argument.
3. **Several fields:** a group is one field's value. The duplicate check reads invoices by supplier, which is enough for it, but a group by two fields (supplier and invoice number) would be finer. Is one field enough?

## Decision

Not yet decided.

## Implementation

Not yet implemented. The model is in `0013/formal`.

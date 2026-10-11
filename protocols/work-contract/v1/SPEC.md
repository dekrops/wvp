# Work Contract Language 1

|                      |                                                                           |
| -------------------- | ------------------------------------------------------------------------- |
| Identifier           | `work-contract-1`; evaluation semantics `kleene-1`                        |
| Version              | 1                                                                         |
| Status               | Draft                                                                     |
| Depends on           | [`verified-json-v1`](../../canonical-json/v1/SPEC.md)                     |
| Normative references | FIPS 180-4 (SHA-256)                                                      |
| Conformance          | [`test-vectors/work-contract/v1`](../../../test-vectors/work-contract/v1) |

Status: draft. Identifier: `work-contract-1`. Evaluation semantics: `kleene-1`.

A **work contract** in this language states, as data, what must be true for a unit of work to count as done. Given a contract and an **environment** of admitted records, evaluation yields one of three decisions, or refuses. There is no executable code in a contract, no recursion and no user-defined function.

Implementation status: three implementations. Scala (`modules/contract-language`) is the operational one; JavaScript (`tooling/work-contract.mjs`) exists so that a second party's tooling can verify a package. Lean 4 (`formal/lean/Verified/Contract`) holds the definition of evaluation (section 7, steps 7 and 8), with checked proofs about it, and a reference evaluator for the whole language. All three must reproduce every outcome in `test-vectors/work-contract/v1`. Where this text and the Lean definition of evaluation disagree, the Lean definition is right and this text is to be corrected. [Work Verification Protocol v0.2](../../wvp/v0.2/SPEC.md) carries these contracts in a portable package. No flow in the product produces such packages yet.

## 1. Decisions

| Decision       | Meaning                                                                  | Elsewhere called |
| -------------- | ------------------------------------------------------------------------ | ---------------- |
| `SUPPORTED`    | Every requirement is established by accepted evidence.                   | verified         |
| `CONTRADICTED` | At least one requirement is conclusively false under accepted evidence.  | rejected         |
| `UNDETERMINED` | Neither: the accepted evidence does not settle at least one requirement. | indeterminate    |

The names are the protocol's. A **refusal** (section 8) is not a decision: an ill-formed contract or environment says nothing about the work.

## 2. Contract

A contract is a JSON object with exactly these members. Each is a separate concern, and all of them are covered by the digest (section 9).

| Member       | Concern               | Content                                                                                          |
| ------------ | --------------------- | ------------------------------------------------------------------------------------------------ |
| `language`   | Language version      | `"work-contract-1"`                                                                              |
| `identity`   | Identity and version  | `{ "id", "version" }`                                                                            |
| `inputs`     | What a claim supplies | name → type. Values come with each claim (an invoice number, a cutoff).                          |
| `kinds`      | Vocabulary            | name → `{ "key": [field…], "fields": { name → type } }`. The kinds of record the contract reads. |
| `evidence`   | Evidence requirements | `{ "conflicts", "sources": { kind → [source…] } }`. Which sources count for which kind.          |
| `policy`     | Policy parameters     | name → `{ "policy": { "id", "version" }, "type", "value" }`. Values are in the contract.         |
| `evaluation` | Evaluation semantics  | `{ "semantics": "kleene-1", "cutoff"?: input name }`                                             |
| `requires`   | Contract semantics    | `[ { "id", "predicate" } … ]`, in ascending order of `id`. Every requirement is mandatory.       |

A contract refers to nothing outside itself. A policy parameter carries its value together with the policy and version the value was taken from; there is no lookup at evaluation time. A new policy version, a new vocabulary or a new language version is a new contract with a new digest. Titles, explanations and approvals are not in the contract (section 10).

Kinds are not tied to any system. An adapter for a particular ERP maps its records to a contract's kinds; the contract names the sources it accepts, not their schemas.

## 3. Types and values

| Type                                          | Values                                                  | Comparisons |
| --------------------------------------------- | ------------------------------------------------------- | ----------- |
| `{"type":"text"}`                             | JSON string, at most 1024 UTF-8 bytes                   | `eq`, `ne`  |
| `{"type":"bool"}`                             | JSON `true` / `false`                                   | `eq`, `ne`  |
| `{"type":"int"}`                              | number                                                  | all six     |
| `{"type":"time"}`                             | non-negative number: seconds since 1970-01-01T00:00:00Z | all six     |
| `{"type":"decimal","scale":s}`                | number of units of 10⁻ˢ                                 | all six     |
| `{"type":"money","currency":"EUR","scale":s}` | number of units of 10⁻ˢ of the currency                 | all six     |

A **number** is a JSON string matching `-?(0|[1-9][0-9]{0,18})`, other than `"-0"`, whose value lies strictly between −2⁶³ and 2⁶³. There are no JSON numbers, fractions or exponents anywhere a value appears: `12.50 EUR` at scale 2 is `"1250"`. `scale` is between 0 and 18; `currency` is three capital letters.

Two values can be compared only if their types are identical, including currency and scale. This is checked when the contract is compiled, so evaluation never converts, rounds or compares across currencies. Text equality is exact, code point for code point, without normalization or case folding.

A field type may carry `"optional": true`. A record may omit an optional field; the member is absent, never `null`, and `"optional": false` is not a valid spelling.

Names (inputs, kinds, fields, parameters, sources, variables, requirement and record identifiers) match `[A-Za-z][A-Za-z0-9_.-]{0,63}`.

## 4. Terms and predicates

A **term** is one of:

| Form                               | Meaning                                      |
| ---------------------------------- | -------------------------------------------- |
| `{"lit": value, "of": type}`       | A literal.                                   |
| `{"input": name}`                  | A value supplied by the claim.               |
| `{"param": name}`                  | A policy parameter's value.                  |
| `{"var": variable, "field": name}` | A field of the record bound to the variable. |

A **predicate** is one of:

| Form                                                   | Meaning                                       |
| ------------------------------------------------------ | --------------------------------------------- |
| `{"cmp": op, "left": term, "right": term}`             | `op` is `eq`, `ne`, `lt`, `le`, `gt` or `ge`. |
| `{"and": [predicate, …]}`, `{"or": [predicate, …]}`    | At least one argument.                        |
| `{"not": predicate}`                                   |                                               |
| `{"exists": variable, "in": kind, "where": predicate}` | Some record of the kind satisfies the body.   |
| `{"forall": variable, "in": kind, "holds": predicate}` | Every record of the kind satisfies the body.  |

Quantifiers range over the finite set of accepted records of one kind, so every quantifier is bounded. Relationships between objects are equalities between fields (`r.posting = p.document`); event order and temporal constraints are comparisons between times; authorization is the existence of a record from a source the contract accepts for it. There is no arithmetic, no aggregation and no set literal in this version (section 12).

## 5. Static rules

A contract is **well formed** when all of the following hold. They are decidable from the contract alone.

1. `language` and `evaluation.semantics` are the identifiers above; names are valid; no name is both an input and a policy parameter.
2. Every kind has at least one field and a non-empty key of distinct, declared, non-optional fields.
3. Every kind has a non-empty list of distinct accepted sources, and `evidence.sources` names no other kind.
4. Every policy parameter's value fits its type and names its policy and version.
5. `evaluation.cutoff`, if present, names an input of type `time`.
6. `requires` is non-empty and its identifiers strictly ascend.
7. In every predicate: each quantifier's kind is declared; its variable is not already bound; each field belongs to its variable's kind; each input and parameter is declared; both sides of a comparison have the same type; `lt`, `le`, `gt`, `ge` are used only on ordered types.
8. No requirement is the negation of another, and no conjunction contains a predicate and its negation. This is a syntactic check, not a satisfiability check.
9. Limits: at most 512 predicate nodes in total, quantifiers nested at most 3 deep, 32 kinds, 32 fields per kind, 64 requirements.

A predicate with a node more than 64 levels below its requirement is not read at all (`CONTRACT_MALFORMED`), so that a reader's own recursion is bounded before any rule is checked. A type's `scale` is a JSON number with a whole value; a string is not a scale.

An implementation must not evaluate a contract that is not well formed.

## 6. Environment

An environment is what a contract is evaluated against:

```json
{
  "inputs": { "invoice": "INV-1001", "cutoff": "1767225600" },
  "facts": [
    {
      "id": "f1",
      "kind": "invoice",
      "source": "sap-s4",
      "fields": { "number": "INV-1001" }
    }
  ],
  "complete": [{ "kind": "reversal", "source": "sap-s4", "asOf": "1767225600" }]
}
```

`facts` are in strictly ascending order of `id`; `complete` is in strictly ascending order of (`kind`, `source`); there are at most 10 000 facts.

A fact is a record a source reported. A **completeness statement** is a source's assertion that the environment holds every record of that kind it has for this claim, as of a time. It matters because of what its absence means: without it, not finding a record shows nothing.

The environment is the result of admission. Who signed a record, and whether the signer may speak for the source it names, is decided before evaluation ([evidence statements](../../../docs/spec/evidence-statement-v1.md)); this language sees only the source name that admission established. How signed statements become an environment is defined by [protocol v0.2, section 2](../../wvp/v0.2/SPEC.md#2-from-signed-statements-to-an-environment).

## 7. Evaluation

Given a well-formed contract and an environment, in this order:

1. **Inputs.** The environment's inputs must be exactly the declared ones, each fitting its type. Otherwise refuse (`ENVIRONMENT_NONCONFORMING`).
2. **Acceptance.** A fact whose kind is not declared, or whose source is not accepted for its kind, is **ignored**: set aside, listed in the result, and never examined further. It cannot establish anything and it cannot cause a refusal.
3. **Conformance.** Every other fact must carry all required fields of its kind, no undeclared field, and values fitting their types. Otherwise refuse (`ENVIRONMENT_NONCONFORMING`).
4. **Work bound.** Let _n_ be the number of facts in the environment (at least 1), _d_ the deepest quantifier nesting, and _s_ the total number of predicate nodes. If _s_ · _nᵈ_ > 10 000 000, refuse (`WORK_LIMIT`).
5. **Conflicts.** Accepted facts of one kind with equal key fields describe one object. If all of them have identical fields they are one record. If they differ, that is a **conflict**, reported in the result and settled by `evidence.conflicts`:
   - `unknown`: none of them is used.
   - `source-order`: the facts from the source listed first for the kind, among those present, are used if they are identical to one another; otherwise none is used.

   A kind with a conflict that was not settled is **open**, whatever its completeness statements say.

6. **Closed kinds.** A kind is **closed** if it is not open and some completeness statement for it comes from a source accepted for it, with `asOf` not earlier than the cutoff input when the contract declares a cutoff.
7. **Requirements.** Each requirement's predicate is evaluated to `TRUE`, `FALSE` or `UNKNOWN`:

   - **Comparison.** If either term is an absent optional field: `UNKNOWN`. Otherwise `TRUE` or `FALSE`.
   - **Connectives** (strong Kleene):

     | `and`       | TRUE    | FALSE | UNKNOWN |     | `or`        | TRUE | FALSE   | UNKNOWN |     | `not`   |         |
     | ----------- | ------- | ----- | ------- | --- | ----------- | ---- | ------- | ------- | --- | ------- | ------- |
     | **TRUE**    | TRUE    | FALSE | UNKNOWN |     | **TRUE**    | TRUE | TRUE    | TRUE    |     | TRUE    | FALSE   |
     | **FALSE**   | FALSE   | FALSE | FALSE   |     | **FALSE**   | TRUE | FALSE   | UNKNOWN |     | FALSE   | TRUE    |
     | **UNKNOWN** | UNKNOWN | FALSE | UNKNOWN |     | **UNKNOWN** | TRUE | UNKNOWN | UNKNOWN |     | UNKNOWN | UNKNOWN |

     For several arguments: `and` is `FALSE` if any is `FALSE`, otherwise `UNKNOWN` if any is `UNKNOWN`, otherwise `TRUE`; `or` is the dual.

   - **`exists`** over kind _K_: `TRUE` if the body is `TRUE` for some record. Otherwise `UNKNOWN` if the body is `UNKNOWN` for some record **or _K_ is not closed**. Otherwise `FALSE`.
   - **`forall`** over kind _K_: `FALSE` if the body is `FALSE` for some record. Otherwise `UNKNOWN` if the body is `UNKNOWN` for some record **or _K_ is not closed**. Otherwise `TRUE`.

   So a witness establishes an `exists` and a counterexample refutes a `forall` whatever else is unknown, but "there is none" and "all of them" can only be concluded from a listing a source declared complete. Missing evidence never becomes `FALSE`.

8. **Decision.** `CONTRADICTED` if any requirement is `FALSE`; otherwise `UNDETERMINED` if any is `UNKNOWN`; otherwise `SUPPORTED`.

The result is `{ "decision", "requirements": [{ "id", "value" }…], "ignored": [fact id…], "conflicts": [{ "kind", "facts": [id…], "resolvedTo"?: id }…] }`.

Evaluation reads no clock, random value, network or stored state. The cutoff is an input.

## 8. Refusals

| Code                        | When                                                                           |
| --------------------------- | ------------------------------------------------------------------------------ |
| `CONTRACT_MALFORMED`        | Not a contract: not JSON of the forms in sections 2 to 4.                      |
| `CONTRACT_ILL_FORMED`       | A contract that breaks a static rule (section 5).                              |
| `ENVIRONMENT_MALFORMED`     | Not an environment of the form in section 6.                                   |
| `ENVIRONMENT_NONCONFORMING` | Inputs or accepted facts that do not fit the contract (section 7, steps 1, 3). |
| `WORK_LIMIT`                | The work bound is exceeded (section 7, step 4).                                |

Checks are made in the order of the table. The result is `{ "refused": code }`.

## 9. Canonical form and digest

The canonical form of a contract is its JSON object under `verified-json-v1` ([Canonical JSON](../../canonical-json/v1/SPEC.md)): keys sorted, no insignificant whitespace, UTF-8. The **contract digest** is the SHA-256 of those bytes.

Because numbers are strings, requirement order is fixed, absent members have one spelling and unknown members are errors, a contract has exactly one canonical text. A reader of contract text must refuse a text that parses to a valid contract but is not its canonical bytes.

The digest identifies the text, not the meaning: two contracts that would decide every environment alike but are written differently have different digests. What the digest guarantees is the converse: the same digest is the same language version, vocabulary, accepted sources, conflict policy, policy values and versions, evaluation semantics and requirements.

## 10. Artifact, clarifications and approval

Compiling a contract produces **errors** (static rules; the contract is not valid) and **clarifications**: questions the contract's shape raises that only the parties can answer. The compiler never answers one and never supplies a missing rule or value.

| Clarification    | Raised when                                                                                        |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `C_COMPLETENESS` | A requirement can be `TRUE` only if some kind is declared complete. Which source can declare that? |
| `C_EVENT_ORDER`  | Two kinds with times concern the same input and nothing orders them. Must one precede the other?   |
| `C_AFTER_CUTOFF` | A kind with times is never related to the cutoff. Do records dated after it count?                 |
| `C_CONSTANT`     | A requirement refers to no evidence.                                                               |
| `C_UNUSED`       | An input, a policy parameter or a kind is declared and never used. Is a rule missing?              |

An **artifact** (`work-contract-artifact-1`) is `{ "artifact", "contract", "digest", "acknowledgements", "approvals", "presentation" }`. It can be produced only when every clarification has an answer from the parties and at least one approval is recorded. Reading an artifact recomputes the digest, checks the contract again and checks the answers again.

`presentation` (title, summary, an explanation per requirement), the answers and the approvals are outside the digest: rewording a title does not change what was agreed. In this version an approval is a record of who approved and when, not a signature.

## 11. Finding where two readings differ

A sentence such as "an invoice is processed when it has been approved and posted" has several readings. Written as contracts, they can be evaluated against the same situations; the situations on which they decide differently are the ambiguity, shown concretely. `examples/approved-and-posted` holds three readings and `differences.json`, the situations that separate them, found by bounded mutation of one base situation (each record removed, each completeness statement withdrawn, each time moved just before and just after every other time). The search is an extension point; no solver is used.

## 12. Not in this version

Arithmetic (so a variance must be a recorded field; it cannot be computed from two amounts); durations and "within _n_ days"; aggregation and counting; set literals and membership; text order and pattern matching; optional requirements and weights; the list of records that established each requirement. Each of these is a language change and therefore a new version.

## 13. What a decision establishes

`SUPPORTED` means: under this contract, the admitted records from the accepted sources establish every requirement. It does not mean the sources told the truth, that a completeness statement was honest, that the contract was the right definition of the work, or that the environment contains everything the sources know. Those rest on admission, on the parties' choice of sources, and on the relying party.

A decision is also not final. It answers one question: this contract, these inputs (the cutoff among them), this evidence. Later evidence can change it: a record that conflicts with an earlier one, a record that shows a completeness statement was wrong, or a withdrawn completeness statement. What does hold is narrower and is proved for the formal definition: if none of those happens and the question is unchanged, admitting more evidence does not change a `SUPPORTED` or `CONTRADICTED` decision.

## 14. Conformance

`test-vectors/work-contract/v1/cases` holds one file per case: `description`, `contract`, `environment`, `expected`. `differential` holds generated batches: `contract` and `cases: [{ environment, expected }]`. A conforming evaluator reproduces `expected` for every case. The corpus covers each decision, each refusal, both conflict policies, ignored records, completeness and the cutoff, the truth tables, second spellings and limits, and the invoice-processing example (`examples/invoice-processing`). Never regenerate published expectations: a change of outcome is a new language version.

What is proved about the definition, and what only agreement on this corpus supports, is listed in formal/lean/README.md.

# RFC 0015: System models

|            |                                                  |
| ---------- | ------------------------------------------------ |
| RFC        | 0015                                             |
| Status     | Draft                                            |
| Author     | Zin Nam                                          |
| Created    | 2026-11-20                                       |
| Affects    | New: `system-model-1`. Nothing existing changes. |
| Supersedes | Nothing                                          |

A new specification, `system-model-1`: the open format of a **system model**, a versioned, signed description of a system or a landscape of systems. It says which kinds of record the system has, which sources report them, who can create, delete and write them, when a source can list a kind completely, and what that rests on. A model commits to each of its parts separately, so a package can disclose exactly the parts a decision used and withhold the rest. It answers open question 1 of [RFC 0014](https://github.com/dekrops/wvp/pull/57), and proposes the design for review without publishing it.

## Motivation

A Work Contract names kinds and sources. What makes those names mean something lives outside the protocol:

| #   | Today                                                                                                                                           | Consequence                                                                   |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| E1  | A contract declares its kinds inline. Nothing says they match a system's records                                                                | Two contracts over one system disagree on its vocabulary                      |
| E2  | The registry says who may speak for a source, not who can **create, delete or write** what it reports                                           | A contract can accept a record the checked party can set                      |
| E3  | A kind's key is the author's choice. [RFC 0008](https://github.com/dekrops/wvp/pull/47) shows a coarse key making two payments one (vector 283) | Undercounting no check catches                                                |
| E4  | Nothing says whether a source can list a kind completely at all                                                                                 | A contract needing a kind closed is approved over sources that never close it |
| E5  | RFC 0014 names a `system-model` by digest and defines none                                                                                      | A recomputed decision depends on material the verifier may not hold           |

A model's content (mappings to records, authority and completeness rules, templates, reports, proofs) is costly to maintain and may be licensed. The protocol stays open and domain-neutral: it specifies the **interface** every model has and what a verifier needs from one, and no model's content.

The concepts are those of the paper _Formalized Environments_ (Verified; not public): a formalized environment is "a bounded, versioned model of what can happen in a process, how it is observed, and which sources carry authority". A system model is the paper's formalized environment; the name avoids a clash with Language 1's _environment_, the records a contract is evaluated against. This RFC takes from it **authority-typed evidence**; the **interested set**, the parties whose payoff depends on a verdict, whose writes are never authoritative for it; **contract-relative authority**; composition; and "formalized is not frozen".

## What changes

A new specification, `system-model-1`, in the family's encodings with [RFC 0002](0002-inputs-every-verifier-refuses-alike.md) applied from the start: `verified-json-v1`, digests as `{ "algorithm": "sha-256", "hex" }` (RFC 0014 decides the same), Ed25519 signatures as `{ "scheme", "keyId", "encoded" }`, canonical instants, integers from 1 to 2^53 − 1. Each object defined here names its format in a member `protocol`.

### 1. The model and its identity

A model is a signed **head** and a set of **parts**. The head holds the identity and an index of the parts:

```json
{
  "model": {
    "protocol": "system-model-1",
    "id": "example.tickets",
    "version": 3,
    "namespace": "tickets",
    "issuer": "model-issuer-1",
    "issuedAt": "2026-11-20T10:00:00Z",
    "supersedes": {
      "kind": "system-model",
      "id": "example.tickets",
      "digest": { "algorithm": "sha-256", "hex": "…" }
    },
    "components": [],
    "parts": [
      {
        "path": "connector/1",
        "digest": { "algorithm": "sha-256", "hex": "…" }
      },
      {
        "path": "kind/approval",
        "digest": { "algorithm": "sha-256", "hex": "…" }
      },
      { "path": "roles", "digest": { "algorithm": "sha-256", "hex": "…" } }
    ]
  },
  "signature": { "scheme": "Ed25519", "keyId": "…", "encoded": "…" }
}
```

- **`id`** matches Language 1's name pattern. It finds a model and never names one: two issuers can choose the same identifier.
- **`namespace`** (`[a-z][a-z0-9-]{0,14}`) qualifies the model's names when it is bound directly (sections 3 and 6).
- **The model digest** is SHA-256 of the canonical `model` member, the "SHA-256 of its canonical form" of RFC 0014.
- **`parts`** ascends by `path`, no path twice. A part's digest is SHA-256 of its canonical object.
- **The signature** is over `verified:system-model:v1\n` and the canonical `model` member.

**Who signs.** A key counts for a model if the relying party's registry holds it, for the verification's tenant, with the head's `issuer`, with `system-model` among its `sources` (a role, not a system), valid at `issuedAt`. A model issuer is registered as an evidence issuer is, never by the model.

**Versions.** A model is never edited. A change is a new head with the same `id`, `namespace` and `issuer`, the next `version`, and `supersedes` naming the previous head. A contract stays bound to the version it was approved against; whether a later one may stand in is the contract's decision (sections 4 and 7).

### 2. Parts, and what is public

Every part is a canonical object with `part`, its path, and `nonce`, the base64 of 16 random octets, so a digest discloses nothing of a guessable part.

| Path                                                                                        | Content                                               | Format           | Needed to verify               |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------- | ------------------------------ |
| `roles`                                                                                     | The classes of actor in the system                    | `system-model-1` | When a contract uses the model |
| `kind/<name>`                                                                               | Fields, identity, sources, authority, completeness    | `system-model-1` | When a contract uses the kind  |
| `assumption/<name>`                                                                         | A stated assumption a kind rests on                   | `system-model-1` | When a used kind names it      |
| `behavior/<name>`                                                                           | Reserved: traces and transitions, for a later version | Not defined      | Never in this version          |
| `connector/<label>`, `template/<label>`, `report/<label>`, `proof/<label>`, `other/<label>` | Mappings, templates, reports, proofs                  | Not defined      | Never                          |

An **opaque part** is `{ part, nonce, media, size, content }`, `content` being the SHA-256 of octets never read here. It commits a model version to exactly that connector without disclosing it. A `behavior/` part is read as an opaque part, so a later version can define it without a new head format.

**Format** and **disclosure** are separate questions. Any part may be withheld until a decision uses it; an opaque part never has to be disclosed. Content is its issuer's, and nothing here grants a licence.

**Selective disclosure.** The head is the proof of inclusion: a part is the model's when its digest is the one listed under its path. Paths are unique and visible, so a disclosed `kind/approval` is the model's only definition of that kind. Of withheld parts the head reveals paths, digests and number. Two things leak by design:

- **Paths.** A label says something by itself. Until a tree hides paths (open question 2), give opaque parts neutral labels: `connector/1`, not `connector/<vendor-product>`.
- **Change history.** Step 6 needs an unchanged part to keep its digest, so its nonce: anyone holding two heads sees which parts changed, connectors included. That is the price of interface-preserving successors; re-noncing every part each version would hide it, and make every version changed.

### 3. The interface parts

**`roles`** is `{ part, nonce, roles: { name → { text } } }`: the requester of a ticket, its assignee, the system itself. The role `anyone` is defined in every model and stands for actors the model cannot enumerate.

**`kind/<name>`**:

```json
{
  "part": "kind/approval",
  "nonce": "kq3Yb4mXGm1sV9cS0p2a0Q==",
  "identity": ["id"],
  "fields": {
    "id": { "type": { "type": "text" } },
    "ticket": { "type": { "type": "text" } },
    "verdict": { "type": { "type": "text" } },
    "at": { "type": { "type": "time" }, "time": "recorded" }
  },
  "sources": {
    "api": {
      "creators": ["approver"],
      "deleters": [],
      "writers": {
        "id": ["system"],
        "ticket": ["system"],
        "verdict": ["approver"],
        "at": ["system"]
      },
      "decisions": { "verdict": "approver" },
      "complete": { "per": "ticket", "asOf": "recorded" }
    }
  },
  "assumptions": ["ids-never-reused"]
}
```

| Member                 | Meaning                                                                                                                                                                                                                                                       |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fields`               | Name to a Work Contract type, as the language spells it. A `time` field means the `event` or when the system `recorded` it                                                                                                                                    |
| `identity`             | The fields that identify one item in the system: one record per item, never one for two                                                                                                                                                                       |
| `sources`              | Each source that reports the kind. A source supplies every field                                                                                                                                                                                              |
| `creators`, `deleters` | Every role that can make a record of the kind appear in, or disappear from, what this source reports                                                                                                                                                          |
| `writers`              | Per field, every role that can determine its value as this source reports it, **including where the source copies what another role wrote**: a bank's remittance reference, copied from the payer's file, lists the payer                                     |
| `decisions`            | Fields recording one role's decision, which the source records when it is made and never rewrites                                                                                                                                                             |
| `complete`             | `null` if the source cannot list the kind completely. Otherwise `asOf`, `event` or `recorded`, and optionally `per`: one field, by whose values the source lists each group completely ([RFC 0013](https://github.com/dekrops/wvp/pull/56)), but not the kind |
| `assumptions`          | The assumption parts the definition rests on                                                                                                                                                                                                                  |

**`assumption/<name>`** is `{ part, nonce, text }`, with an optional `predicate` over the model's kinds, for tools; no verifier evaluates it. It states what a verdict rests on that evidence does not show, such as that identifiers are never reused. Authority goes in `creators`, `deleters` and `writers` instead, which admission checks: an append-only approval source has no deleters.

In a model's parts, names are bare. Outside, they are qualified: kind `tickets.approval`, source `tickets.api`, role `tickets.approver`. Statements carry the qualified source in `source.system`, and records the qualified kind, so a connector writes the names a contract reads.

### 4. References

**A contract** pins a **binding** by a policy parameter named `systemModel`. Languages 1 and 2 need no change: a policy parameter "carries its value together with the policy and version the value was taken from", which is what this is.

```json
"systemModel": {
  "policy": { "id": "example.tickets", "version": "3" },
  "type": { "type": "text" },
  "value": "5c1e…"
}
```

`value` is the `hex` of the binding's digest `{ "algorithm": "sha-256", "hex" }`: a Language 1 value is a scalar, so `system-model-1` fixes the algorithm. `policy` names the **bound** head: its `id`, and its integer `version` as a Language 1 policy version, the decimal numeral without leading zeros (`3` is `"3"`). The binding:

```json
{
  "protocol": "system-model-binding-1",
  "model": {
    "kind": "system-model",
    "id": "example.tickets",
    "digest": { "algorithm": "sha-256", "hex": "…" }
  },
  "interested": ["tickets.approver"],
  "actors": ["tickets.assignee"],
  "decides": ["tickets.approver"],
  "claims": {},
  "successors": true
}
```

`model` is RFC 0014's reference, in work relation v1's shape `{ kind, id, digest }`. `interested` lists the contract's interested roles; `actors`, the roles whose work it checks, interested whether listed there or not; `decides`, the roles whose recorded decisions it assigns to them; `claims`, what it reads as claims (section 5); `successors`, whether a later version may stand in when no part the contract uses changed (section 7).

The binding's digest is inside the contract's, so whatever pins a contract pins the model version and the interested set with it.

A bound contract still declares its kinds inline. A kind whose name has a `.` (`tickets.approval`) is **model-bound** and checked; a kind without one is **inline-only** and unchecked, as today. A contract may mix both.

**A package** travels with a **disclosure**, `{ "disclosure": { "protocol": "system-model-disclosure-1", binding, heads, parts } }`: the binding, every head from the bound model to each used part (section 6), and the used parts. The contract pins the binding, the binding the head, the heads the parts. `wvp-0.2` is unchanged and the disclosure travels beside it; a later package version may make it a component.

**A ledger entry** names a model by RFC 0014's `system-model` reference, and a contract by its digest, which pins the model through the binding. A `pin.set` entry can record the version in force. Replay never opens a reference.

### 5. Authority for a contract

For a contract _c_ with binding _B_, let _I_ be the roles in `B.interested` and `B.actors`, and `anyone`. For a model-bound kind _k_ and a source _S_ the contract accepts for it:

- **Fields.** For a field _f_ the contract declares, let _W_ be its writers from _S_, without any role of `B.decides` whose decision _S_ records in _f_. _f_ is **authoritative for _c_ from _S_** if and only if _W_ and _I_ share no role.
- **Existence.** Let _C_ be the creators of _k_ from _S_, without any role of `B.decides` whose decision _S_ records in _k_, and _D_ its deleters. _k_ is **authoritative for existence** if and only if neither _C_ nor _D_ shares a role with _I_. Deletion has no exception.

Admission requires every declared field, and the existence of every model-bound kind, to be authoritative from every source accepted for it, unless the binding declares it a claim. Existence matters as much as fields: a role that can create an approval makes `exists` true, and a closed listing is only as good as the guarantee that nobody interested removed a record.

Authority is therefore contract-relative. `verdict` records the approver's decision: a contract that assigns it may rely on it although the approver, acting for the principal, is interested. A contract about the approver's own work lists the approver among `actors`, cannot assign it the decision, and can read `verdict` only as a claim. A contract checking the assignee cannot accept a ticket's `state` the assignee can set, whoever the registry lets speak for the source.

The decision exception is the paper's: a record of a decision the contract assigns to a party counts if committed when made. The model says which fields are such records, the contract which roles it assigns. A record of whether the contracted work was done is never one, so a role in both `actors` and `decides` is refused (`DECISION_BY_ACTOR`). The report lists roles both interested and assigned (`decisionByInterested`), as `wvp-0.3` reports `claimantAlsoSource`.

**Claims.** Some contracts read non-authoritative fields on purpose, as the thing under check: "the invoice's net and tax add up to its gross" reads three fields the interested supplier writes. The binding declares them:

```json
"claims": { "ap.invoice": { "fields": ["gross", "net", "tax"] } }
```

`claims` maps a model-bound kind to declared fields and, with `"existence": true`, its existence, which makes all its fields claims. A claim is read, never relied on as evidence: the rule above does not apply, and the report lists it with the interested roles that can create, delete or write it. It may be compared with fields of the same record, inputs, policy parameters and constants. It may not:

1. **be the source of a fact about other records,** by appearing in a comparison or term with another record's field: `i.net + i.tax = i.gross` is admitted, `p.amount ≤ i.gross` and `p.invoice = i.number` are not;
2. **close a kind:** be a quantifier's or aggregate's `per` field, since its writer chooses the group; nor, for a claimed existence, be read where the listing must be closed (`C_COMPLETENESS`).

Either is `CLAIM_RELIED_ON`. A decision over claims shows that a claim is consistent, not that it is true.

### 6. Landscapes

A **landscape** is a model whose `components` name other models, each as `{ "alias", "model" }`, `model` being a `system-model` reference, ascending by `alias`. An alias follows the `namespace` pattern, appears once, and differs from the landscape's `namespace`. The landscape assigns each component the namespace its names resolve under, so two vendors' models that both call themselves `bank` compose as `payer-bank` and `payee-bank`. Its own parts, such as a reconciliation of invoices with payments, are in its own namespace. In them, a name with a `.` is a component's (`payer-bank.payer`); a derived kind lists the creators, deleters and writers of everything it derives from.

1. **Names** resolve through aliases from the bound model: `payer-bank.payer`, or `erp.bank.payer` one level down. The same digest reached twice is one model, whichever aliases reach it, so resolution is a function.
2. **Conflict is a refusal.** Two reachable models with one `id` and `issuer` and different digests, two versions of one model, refuse the landscape (`COMPOSITION_CONFLICT`). Components on a shared base use one version of it (open question 9). Nothing is merged or preferred.
3. **No redefinition.** A landscape cannot change a component's part; it names its own.
4. **Acyclic by construction.** A head commits to its components' digests, so no model reaches itself.
5. **Contracts over several systems** bind the landscape and name kinds and sources from any model in it. Authority is computed from the model that defines the kind; the interested set lists roles of every model the contract reads.

A part of a component is included when its digest is in its head's index and that head's digest is in its parent's `components`, up to the bound head.

### 7. The admission check

Admission takes a contract, a disclosure (or the whole model) and the relying party's registry. It runs at contract approval, as a gate, and beside package verification, whose result it never changes. A contract without the parameter is `NOT_BOUND`, not refused.

The **bound head** is the one the binding names; the **head used** is the bound head or, if the binding allows, a successor of it. The **used parts** are `roles`, `kind/<k>` for each model-bound kind, and the assumptions those name, under the head used. Checks run in this order and stop at the first failure:

| Step | Check                                                                                                                                                                                                                          | Refusal                                                                                   |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| 1    | Within the limits                                                                                                                                                                                                              | `LIMIT`                                                                                   |
| 2    | Parameter, disclosure, binding, heads and parts are canonical, with exactly their members and types; each `protocol` is its object's                                                                                           | `MALFORMED`, `UNSUPPORTED_PROTOCOL`                                                       |
| 3    | The binding's digest is the parameter's value; the bound head is present, and its `id` and `version` are the parameter's `policy`, compared as section 4 says                                                                  | `BINDING_MISMATCH`, `MODEL_MISSING`                                                       |
| 4    | Every other head needed is present                                                                                                                                                                                             | `MODEL_MISSING`                                                                           |
| 5    | Each signature under a registered key counts                                                                                                                                                                                   | `MODEL_SIGNATURE_INVALID`                                                                 |
| 6    | If the head used is not the bound one: the binding allows successors; `supersedes` leads back to the bound head under one `id`, `namespace` and `issuer`; each later head is signed by a key that counts; no used part changed | `SUCCESSOR_NOT_ALLOWED`, `NOT_A_SUCCESSOR`, `SUCCESSOR_NOT_ENDORSED`, `USED_PART_CHANGED` |
| 7    | Section 6, rules 2 and 4                                                                                                                                                                                                       | `COMPOSITION_CONFLICT`                                                                    |
| 8    | Every used part is disclosed, with the digest its head lists under its path                                                                                                                                                    | `PART_MISSING`, `PART_NOT_COMMITTED`                                                      |
| 9    | Every role of the binding is defined; no role is both an actor and assigned decisions                                                                                                                                          | `UNKNOWN_ROLE`, `DECISION_BY_ACTOR`                                                       |
| 10   | A kind with a `.` resolves and is defined there; its fields are among the model kind's, with identical types; its key is the model's `identity`, as a set; each claim names such a kind and fields it declares                 | `UNKNOWN_NAMESPACE`, `UNKNOWN_KIND`, `UNKNOWN_FIELD`, `TYPE_MISMATCH`, `KEY_NOT_IDENTITY` |
| 11   | Every source accepted for a model-bound kind is one of its sources. The package's own completeness statements are deliberately left to `outOfModel`, a finding                                                                 | `SOURCE_NOT_DEFINED`                                                                      |
| 12   | Section 5 for fields and existence, claims excepted                                                                                                                                                                            | `NOT_AUTHORITATIVE`, `EXISTENCE_NOT_AUTHORITATIVE`                                        |
| 13   | Claims are used only as section 5 allows                                                                                                                                                                                       | `CLAIM_RELIED_ON`                                                                         |

A signature under an unregistered key is not counted and not refused: the contract pins the bound model, so a signature is an endorsement, as in `wvp-0.3`. A successor is pinned by nothing, so it must be endorsed.

Step 10 makes RFC 0008's undercounting a refusal: payments keyed by invoice and amount, under a model whose payment identity is its own identifier, are `KEY_NOT_IDENTITY`. A finer key would split one item reported twice.

**The report** states apart: `admission` (`ADMITTED`, `NOT_BOUND` or the refusal); the `bound` and `used` model references; `endorsements` per head; `inline` kinds; `assumptions`, with their text; `claims`; `decisionByInterested`; and three findings:

- **`neverClosed`:** a quantifier or aggregate whose listing must be closed (`C_COMPLETENESS`) that no accepted source can close. A source whose `complete` has no `per` closes any; one with `per` _f_ closes only those with RFC 0013's `per` on _f_.
- **`timeMeaning`:** a requirement compares with the cutoff a `time` field of a kind it needs closed, and the field's meaning (`event` or `recorded`) is not the `asOf` of a source that closes the kind.
- **`outOfModel`**, for a package: a completeness statement claiming more than its source's `complete` allows: any, if that is `null`; one for the whole kind, or for groups by another field, if it has a `per`.

They are findings: a contract may be one-sided by design, and an out-of-model statement means the model or a connector is wrong.

A gate requiring admission MUST fail on anything but `ADMITTED`. A relying party may require a named issuer's endorsement.

**A determinability report** may accompany an approval. The report is opaque here; its public **summary** is not, so an approver can hold the report to it: `{ protocol, contract, model, report, requirements }`, with `protocol` `determinability-summary-1`, the contract's digest, the bound head's reference, the report's digest, and per requirement, ascending by `id`, whether it is `decidable` (`always`, `assuming` or `never`), the `assumptions` it is decidable under, and its `coverage`, `{ decided, cases }`, the report's cases in which it was decided. A verifier checks that the summary names the contract and the bound head, lists each requirement once and names only used assumptions, not that the report is right. Contract approval v1's snapshot is any object with a `contract` member, so it can carry the summary under the approver's signature over `shown`. Neither contract approval v1 nor `ledger-1` changes.

### 8. Conformance

Under [RFC 0004](0004-conformance-profiles.md), rule 3, a new profile, _System-model admission_: the canonical encoding and the `system-model-1` objects, over synthetic models.

A **bound profile** is a set of profiles and exactly one model version, since RFC 0004 has no optional parts: "WVP for merges on system X" is package verification, ledger verification, system-model admission, and the model `{ id, version, digest }` with its own vectors, named by digest. An implementation or a licensed library declares the bound profiles it reproduces, with the corpus commit and the digest of the model's vectors. Where those are licensed, only their holders can check the claim; the public report states the format profile alone.

## What a third party can verify offline

With the contract, the disclosure and its registry:

| Verifiable                                                                             | Not verifiable                                               |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| The model version and interested set the contract was approved with                    | That the model's authority is true of the system             |
| That each disclosed part is the model's, and its only definition at that path          | **That the licensed mapping read the system correctly**      |
| Who issued and signed each version, under its own keys                                 | That a completeness rule or an assumption holds              |
| That the contract's kinds, types, keys and sources fit the model                       | Anything in an undisclosed part                              |
| That every accepted source is authoritative for the contract, for fields and existence | That no later version exists                                 |
| Which fields are claims; that a successor changed no used part                         | That the contract is determinable, beyond its summary's word |

The second right-hand row is the source-accuracy boundary every WVP check has: a model shows what its issuer says the system is, and a wrong mapping produces wrong records that verify. A model adds accountability: its digest commits to the connector, so its holder can later show what it did.

## RFC 0014's open question 1: system models offline

RFC 0014 left two options: (a) the parts a decision depends on travel with the package; (b) relying parties get free, verify-only read access to the model version. This RFC specifies (a), which makes (b) unnecessary **for verification**: everything admission and recomputation read is in the disclosure, checked against a head the contract pins.

(a) leaves withheld parts unknown, and shows the version used, not whether a newer one exists; heads reveal paths, number and changes of withheld parts. (b) makes verification depend on the publisher's availability and terms for as long as decisions are kept, tells the publisher who verifies which decisions, and shows every verifier more than a decision needs. Neither shows that the mapping was right. (b) stays useful, between parties, for what verification does not need: reviewing a model and auditing a mapping.

## Outcomes that change

None. `system-model-1` is a new identifier in a new directory with its own vectors ([RFC 0001](0001-standards-process.md), invariant 2). A bound contract is a valid Language 1 or 2 contract that evaluates as it would without this specification.

New refusal codes: those of section 7.

## Compatibility

- **Inline kinds** stay valid, and the reference is optional. With it, inline kinds remain what evaluation reads; the model constrains them to a subset of its fields, with identical types, keyed by identity. Adopting a model renames kinds and sources: a new contract, approved again.
- **Language 1** raises `C_UNUSED` for the parameter; the parties answer that it binds the model.
- **Producers** name sources and kinds qualified, as the bound model resolves them, and project records onto the contract's fields, since evaluation refuses an undeclared one. A gateway serving two models signs under two source names.
- **Relying parties** register model issuers under `system-model`, for endorsements and successors.
- **RFC 0014**'s `system-model` reference names a `system-model-1` head. **RFC 0013**'s groups, one field's value, are what `per` names. Neither changes.

## Vectors

In `test-vectors/system-model/v1`, over synthetic models of a ticket system, an invoice system and a landscape of both, at least:

- **Admitted:** model-bound kinds only, and mixed with inline-only ones; two components, also with one `namespace` under two aliases; a field authoritative under one binding and refused under another; a decision, and an approval's creation, assigned to an interested role; net + tax = gross as claims; a successor whose connector changed; each finding.
- **Refused,** every code, and: RFC 0008's vectors 282 and 283 under a model whose payment identity is its identifier (282 admitted, 283 `KEY_NOT_IDENTITY`); a key finer than the identity; a field the assignee can write; a copied field listing the payer; a payment an interested role can delete; a claim compared with another record's field, or used as `per`; a part swapped under its path; a bound head of another version; a changed or unendorsed successor; a diamond reaching two versions of one model.
- **Sufficiency:** each admitted case gives one result from its disclosure and from the whole model.
- **Order:** steps 8 and 10 failing at once, 10 and 12, and 12 and 13.

## Security considerations

This RFC touches signing inputs, digests, the trust registry and what a result may be relied on for (RFC 0001, section 9.1). **The adversary** controls every byte of a package and its disclosure, and may be the model issuer. **Assumed:** Ed25519 and SHA-256 hold; the relying party's registry and pins are what it intends.

**Prevented:**

- _A model swapped under a contract._ The contract pins the binding, the binding the model; a successor needs consent, endorsement and unchanged used parts.
- _A part swapped, or shown differently to two verifiers._ A part counts only under its head's digest, at a path that appears once.
- _Accepting a record the checked party can create, delete or write_, once the model lists its role and the contract lists the role as interested; and relying on a claim.
- _Two items counted as one_ through a coarse key.
- _A conflicting composition_ resolved differently by two verifiers.

**Not prevented:**

- _A malicious or wrong model._ A model that omits a writer or a deleter makes a claim look authoritative: a model is its issuer's word. A relying party should register only model issuers outside its contracts' interested sets, and read the used parts before approving.
- _Undisclosed parts hiding a bad mapping._ The digest commits to the mapping; it does not show it is right.
- _A stale model._ A package cannot show its version is the latest; a ledger's `pin.set` can say which is in force.
- _A wrong interested set, actors or claims,_ which the parties approve with the contract.
- _Linkability:_ a disclosure shows which kinds a contract reads; heads show part labels and which parts changed between versions (section 2).

**Primitives.** Ed25519 (RFC 8032, under RFC 0002, rule 1), SHA-256 (FIPS 180-4). None is new.

**Review.** No person other than the author has reviewed this RFC. Under RFC 0001, section 9.1, it cannot become Final until a competent reviewer has, and is named here.

## Formal semantics

Nothing is proved here. Worth proving in Lean, digests injective and signatures assumed:

1. _Sufficiency of disclosure._ Admission is a function of the contract, the binding, the heads on the path and the used parts, so a disclosure gives the whole model's result.
2. _Independence._ If a contract is admitted and the model's authority is correct, nothing an interested role can create, delete or write reaches a requirement except an assigned decision or a claim, and no claim selects or bounds another record: the paper's independence result, as strong as its premise.
3. _Successors._ A successor that passes step 6 gives the bound version's result.
4. _Composition._ Name resolution in an admitted landscape is a function, and no head reaches itself.
5. _Monotonicity._ Adding a role to `interested` or `actors`, or removing one from `decides` or a field from `claims`, can only turn admission into refusal.

**Tested only:** encodings, signatures, limits. **Neither:** that a model is true of its system.

## Alternatives

- **Models inline in every contract.** Each repeats an unchecked vocabulary, and authority and completeness have no place in the language.
- **No model.** Without authority per kind and field there is no contract-relative authority.
- **A member in a new language version.** Cleaner than a parameter, and a new language for what needs no change of evaluation.
- **A public model registry.** One party would decide where models are found and trusted (invariant 7), and its availability would condition verification.
- **Whole models public.** An open format does not need open content.
- **A Merkle tree over parts**, as `ledger-1` uses. A smaller head and hidden paths, but an ordinary tree's inclusion proof cannot show that no other part has the same path.

## Open questions

1. **The parameter,** or a member in a future language; and whether `C_UNUSED` should be silent for it.
2. **Large models.** Thousands of parts make a head of hundreds of kilobytes. A tree keyed by path would shrink it and hide withheld paths.
3. **Valid time.** The paper interprets each observation under the version valid when it was made. A package here uses one version.
4. **Out-of-model evidence:** whether a gate should fail on it, as drift.
5. **Identity across systems,** now an assumption; perhaps a structured link between components' kinds.
6. **Derived kinds** list provenance creators, deleters and writers by hand; the paper computes them.
7. **Assumptions as requirements.** Whether a later version lets a contract require an assumption's `predicate`, as a requirement over the model's kinds, so it is checked on the evidence rather than assumed.
8. **Groups by several fields,** if RFC 0013 grows them; `per` would follow.
9. **Shared bases in several versions.** The successor rule could allow components on different versions of one base when no part the landscape uses changed between them.
10. **Limits.** Proposed: 4,096 parts per head, 64 KiB per interface part, 16 components, 4 levels.

## Decision

Not made. The review period of RFC 0001, section 5, has not started. This RFC will be accepted on the maintainers' judgement alone only if it says that it had no outside review (section 7.4).

## Implementation

Not implemented.

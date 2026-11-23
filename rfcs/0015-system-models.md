# RFC 0015: Environment models, an open format for formalized systems

|            |                                                 |
| ---------- | ----------------------------------------------- |
| RFC        | 0015                                            |
| Status     | Draft                                           |
| Author     | Zin Nam                                         |
| Created    | 2026-11-20                                      |
| Affects    | New: `environment-1`. Nothing existing changes. |
| Supersedes | Nothing                                         |

A new specification, `environment-1`: the open format of an **environment model**, a versioned, signed description of a system or a landscape of systems. It says which kinds of record the system has, which sources report them, who can write each field, when a source can list a kind completely, and what that rests on. A model commits to each of its parts separately, so a package can disclose exactly the parts a decision used and withhold the rest. Contracts, packages and ledger entries name a model only by identifier and digest. It answers open question 1 of [RFC 0014](https://github.com/dekrops/wvp/pull/57), and proposes the design for review without publishing it.

## Motivation

A Work Contract names kinds and sources. What makes those names mean something lives outside the protocol:

| #   | Today                                                                                                                                           | Consequence                                                                   |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| E1  | A contract declares its kinds inline. Nothing says they match a system's records                                                                | Two contracts over one system disagree on its vocabulary                      |
| E2  | The registry says who may speak for a source, not who can **write** what it reports                                                             | A contract can accept a field the checked party can set                       |
| E3  | A kind's key is the author's choice. [RFC 0008](https://github.com/dekrops/wvp/pull/47) shows a coarse key making two payments one (vector 283) | Undercounting no check catches                                                |
| E4  | Nothing says whether a source can list a kind completely at all                                                                                 | A contract needing a kind closed is approved over sources that never close it |
| E5  | RFC 0014 names a `system-model` by digest and defines none                                                                                      | A recomputed decision depends on material the verifier may not hold           |

A model's content (mappings to records, authority and completeness rules, templates, reports, proofs) is costly to maintain and may be licensed. The protocol stays open and domain-neutral: it specifies the **interface** every model has and what a verifier needs from one, and no model's content.

The concepts are those of the paper _Formalized Environments_ (Verified; not public): a formalized environment is "a bounded, versioned model of what can happen in a process, how it is observed, and which sources carry authority". This RFC takes from it **authority-typed evidence**, per system, kind, field and writer; the **interested set**, the parties whose payoff depends on a verdict, whose writes are never authoritative for it; **contract-relative authority**; composition; and "formalized is not frozen".

## What changes

A new specification, `environment-1`, in the family's encodings with [RFC 0002](0002-inputs-every-verifier-refuses-alike.md) applied from the start: `verified-json-v1`, digests as `{ "algorithm": "sha-256", "hex" }`, Ed25519 signatures as `{ "scheme", "keyId", "encoded" }`, canonical instants, integers from 1 to 2^53 − 1.

### 1. The model and its identity

A model is a signed **head** and a set of **parts**. The head holds the identity and an index of the parts:

```json
{
  "model": {
    "protocol": "environment-1",
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
        "path": "connector/rest",
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
- **`namespace`** (`[a-z][a-z0-9-]{0,14}`) qualifies the model's names outside it (section 3).
- **The model digest** is SHA-256 of the canonical `model` member, the "SHA-256 of its canonical form" of RFC 0014.
- **`parts`** ascends by `path`, no path twice. A part's digest is SHA-256 of its canonical object.
- **The signature** is over `verified:environment-model:v1\n` and the canonical `model` member.

**Who signs.** A key counts for a model if the relying party's registry holds it, for the verification's tenant, with the head's `issuer`, with `environment-model` among its `sources` (a role, not a system), valid at `issuedAt`. A model issuer is registered as an evidence issuer is, never by the model.

**Versions.** A model is never edited. A change is a new head with the same `id`, `namespace` and `issuer`, the next `version`, and `supersedes` naming the previous head. A contract stays bound to the version it was approved against; whether a later one may stand in is the contract's decision (sections 4 and 7).

### 2. Parts, and what is public

Every part is a canonical object with `part`, its path, and `nonce`, the base64 of 16 random octets, so a digest discloses nothing of a guessable part.

| Path                                                                                        | Content                                          | Format          | Needed to verify               |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------ | --------------- | ------------------------------ |
| `roles`                                                                                     | The classes of writer in the system              | `environment-1` | When a contract uses the model |
| `kind/<name>`                                                                               | Fields, identity, sources, writers, completeness | `environment-1` | When a contract uses the kind  |
| `assumption/<name>`                                                                         | A stated assumption a kind rests on              | `environment-1` | When a used kind names it      |
| `connector/<label>`, `template/<label>`, `report/<label>`, `proof/<label>`, `other/<label>` | Mappings, templates, reports, proofs             | Not defined     | Never                          |

An **opaque part** is `{ part, nonce, media, size, content }`, `content` being the SHA-256 of octets never read here. It commits a model version to exactly that connector without disclosing it.

**Format** and **disclosure** are separate questions. The first three rows have a format defined here; opaque parts have none. Any part may be withheld until a decision uses it; an opaque part never has to be disclosed. Content is its issuer's, and nothing here grants a licence.

**Selective disclosure.** The head is the proof of inclusion: a part is the model's when its digest is the one listed under its path. Paths are unique and visible, so a disclosed `kind/approval` is the model's only definition of that kind. Of withheld parts the head reveals paths, digests and number.

### 3. The interface parts

**`roles`** is `{ part, nonce, roles: { name → { text } } }`: the requester of a ticket, its assignee, the system itself. The role `anyone` is defined in every model and stands for writers the model cannot enumerate.

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
      "writers": {
        "id": ["system"],
        "ticket": ["system"],
        "verdict": ["approver"],
        "at": ["system"]
      },
      "decisions": { "verdict": "approver" },
      "complete": { "per": ["ticket"], "asOf": "recorded" }
    }
  },
  "assumptions": ["approvals-append-only"]
}
```

| Member        | Meaning                                                                                                                                                                                                                   |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fields`      | Name to a Work Contract type, spelled as the language spells it. A `time` field says whether it means the `event` or when the system `recorded` it                                                                        |
| `identity`    | The fields that identify one item in the system: one record per item, never one for two                                                                                                                                   |
| `sources`     | Each source that reports the kind. A source supplies every field                                                                                                                                                          |
| `writers`     | Per field, every role that can determine its value as this source reports it, **including where the source copies what another role wrote**: a bank's remittance reference, copied from the payer's file, lists the payer |
| `decisions`   | Fields recording one role's decision, which the source records when it is made and never rewrites                                                                                                                         |
| `complete`    | `null` if the source cannot list the kind completely. Otherwise `per`, the fields by whose values it can list a group completely ([RFC 0013](https://github.com/dekrops/wvp/pull/56)), and what `asOf` means              |
| `assumptions` | The assumption parts the definition rests on                                                                                                                                                                              |

**`assumption/<name>`** is `{ part, nonce, text }`, with an optional `predicate` over the model's kinds, for tools; no verifier evaluates it. It states what a verdict rests on that evidence does not show: that approvals are append-only, that identifiers are never reused.

In a model's parts, names are bare. Outside, they are qualified: kind `tickets.approval`, source `tickets.api`, role `tickets.approver`. Statements carry the qualified source in `source.system`, and records the qualified kind, so a connector writes the names a contract reads.

### 4. References

**A contract** pins a **binding** by a policy parameter named `environment`. Languages 1 and 2 need no change: a policy parameter "carries its value together with the policy and version the value was taken from", which is what this is.

```json
"environment": {
  "policy": { "id": "example.tickets", "version": "3" },
  "type": { "type": "text" },
  "value": "sha-256:5c1e…"
}
```

`value` is the binding's digest, in contract approval v1's spelling; `policy` repeats the model's `id` and `version` for a reader. The binding:

```json
{
  "binding": "environment-1",
  "model": {
    "kind": "system-model",
    "id": "example.tickets",
    "digest": { "algorithm": "sha-256", "hex": "…" }
  },
  "interested": ["tickets.approver", "tickets.assignee"],
  "decides": ["tickets.approver"],
  "successors": true
}
```

`model` is RFC 0014's reference, in work relation v1's shape `{ kind, id, digest }`. `interested` lists the contract's interested roles; `decides`, the roles whose recorded decisions it assigns to them (section 5); `successors`, whether a later version may stand in when no part the contract uses changed (section 7).

The binding's digest is inside the contract's, so whatever pins a contract (an expectation, an approval, a ledger entry) pins the model version and the interested set with it.

A bound contract still declares its kinds inline. A kind named `<namespace>.<name>` is **model-bound** and checked; a kind without a `.` is **inline-only** and unchecked, as today. A contract may mix both.

**A package** travels with a **disclosure**, `{ "disclosure": { protocol, binding, heads, parts } }`: the binding, every head from the bound model to each used part (section 6), and the used parts. It needs no reference to the package: the contract pins the binding, the binding the head, the heads the parts. `wvp-0.2` is unchanged and the disclosure travels beside it; a later package version may make it a component.

**A ledger entry** names a model by RFC 0014's `system-model` reference, and a contract by its digest, which pins the model through the binding. A `pin.set` entry can record the version in force. Replay never opens a reference.

### 5. Authority for a contract

For a contract _c_ with binding _B_, let _I_ be `B.interested` and `anyone`. For a model-bound kind, a source _S_ the contract accepts for it, and a field _f_ it declares, let _W_ be the writers of _f_ from _S_. If _f_ is a decision of a role in `B.decides`, remove that role from _W_. Then _f_ is **authoritative for _c_ from _S_** if and only if _W_ and _I_ share no role.

Admission requires every declared field of a model-bound kind to be authoritative from every source accepted for it. A contract declares only fields it may rely on.

Authority is therefore contract-relative. `verdict` records the approver's decision: a contract that assigns it may rely on it although the approver, acting for the principal, is interested; a contract about the approver's own work does not, and there the field is a claim. A contract in which the assignee is interested cannot accept a ticket's `state` that the assignee can set, whoever the registry lets speak for the source.

The decision exception is the paper's: a record of a decision the contract assigns to a party counts if committed when made. The model says which fields are such records, the contract which roles it assigns; a record of whether the contracted work was done is never one. The report lists roles both interested and assigned (`decisionByInterested`), as `wvp-0.3` reports `claimantAlsoSource`.

### 6. Landscapes

A **landscape** is a model whose `components` name other models by reference, ascending by digest. It adds parts in its own namespace: a reconciliation of invoices with payments, an assumption that two systems share an identifier. In its parts, a name with a `.` is a component's (`bank.payer`); a derived kind lists the writers of everything it derives from.

1. **Namespaces.** Every model reachable through `components` has its own. The same digest reached twice is one model.
2. **Conflict is a refusal.** Two reachable models with one namespace and different digests (two versions of one model, or two models that chose one name) refuse the landscape (`COMPOSITION_CONFLICT`). Nothing is merged or preferred.
3. **No redefinition.** A landscape cannot change a component's part; it names its own.
4. **Acyclic by construction.** A head commits to its components' digests, so no model reaches itself.
5. **Contracts over several systems** bind the landscape and name kinds and sources from any model in it. Authority is computed per field from the model that defines the kind; the interested set lists roles of every model the contract reads.

A part of a component is included when its digest is in its head's index and that head's digest is in its parent's `components`, up to the bound head.

### 7. The admission check

Admission takes a contract, a disclosure (or the whole model) and the relying party's registry. It runs at contract approval, as a gate, and when a package is verified, reported beside the package's result, which it never changes. A contract without the parameter is `NOT_BOUND`, not refused.

The **used parts** are `roles`, `kind/<k>` for each model-bound kind, and the assumptions those name. Checks run in this order and stop at the first failure:

| Step | Check                                                                                                                                                                                                                          | Refusal                                                                                   |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| 1    | Within the limits                                                                                                                                                                                                              | `LIMIT`                                                                                   |
| 2    | Parameter, disclosure, binding, heads and parts are canonical, with exactly their members and types; `protocol` is `environment-1`                                                                                             | `MALFORMED`, `UNSUPPORTED_PROTOCOL`                                                       |
| 3    | The binding's digest is the parameter's value; the head's `id` and `version` are the parameter's                                                                                                                               | `BINDING_MISMATCH`                                                                        |
| 4    | Every head needed is present, the bound one with the binding's digest                                                                                                                                                          | `MODEL_MISSING`                                                                           |
| 5    | Each signature under a registered key counts                                                                                                                                                                                   | `MODEL_SIGNATURE_INVALID`                                                                 |
| 6    | If the head used is not the bound one: the binding allows successors; `supersedes` leads back to the bound head under one `id`, `namespace` and `issuer`; each later head is signed by a key that counts; no used part changed | `SUCCESSOR_NOT_ALLOWED`, `NOT_A_SUCCESSOR`, `SUCCESSOR_NOT_ENDORSED`, `USED_PART_CHANGED` |
| 7    | Section 6, rules 1 and 4                                                                                                                                                                                                       | `COMPOSITION_CONFLICT`                                                                    |
| 8    | Every used part is disclosed, with the digest its head lists under its path                                                                                                                                                    | `PART_MISSING`, `PART_NOT_COMMITTED`                                                      |
| 9    | Every role of the binding is defined                                                                                                                                                                                           | `UNKNOWN_ROLE`                                                                            |
| 10   | A kind with a `.` has a known namespace and is defined there; its fields are among the model kind's, with identical types; its key is the model's `identity`, as a set                                                         | `UNKNOWN_NAMESPACE`, `UNKNOWN_KIND`, `UNKNOWN_FIELD`, `TYPE_MISMATCH`, `KEY_NOT_IDENTITY` |
| 11   | Every source accepted for a model-bound kind is one of its sources                                                                                                                                                             | `SOURCE_NOT_DEFINED`                                                                      |
| 12   | Section 5                                                                                                                                                                                                                      | `NOT_AUTHORITATIVE`                                                                       |

A signature under an unregistered key is not counted and not refused: the contract pins the bound model, so a signature is an endorsement, as in `wvp-0.3`. A successor is pinned by nothing, so it must be endorsed.

Step 10 makes RFC 0008's undercounting a refusal. Payments keyed by invoice and amount, under a model whose payment identity is its own identifier, are `KEY_NOT_IDENTITY`. The key must equal the identity, since a finer key splits one item reported twice.

**The report** states apart: `admission` (`ADMITTED`, `NOT_BOUND` or the refusal); the `bound` and `used` model references; `endorsements` per head; `inline` kinds; `assumptions`, with their text; `decisionByInterested`; `neverClosed`, model-bound kinds a requirement needs closed (Language 1's `C_COMPLETENESS`) that no accepted source can close; and, for a package, `outOfModel`, completeness statements from a source whose `complete` is `null`. The last two are findings: a contract may be one-sided by design, and an out-of-model statement says the model or a connector is wrong.

A gate requiring admission MUST fail on anything but `ADMITTED`. A relying party may require a named issuer's endorsement.

**A determinability report** may accompany an approval, opaque here. Contract approval v1's snapshot is any object with a `contract` member, so it can include the report's digest, and the approver's signature over `shown` covers it. Neither contract approval v1 nor `ledger-1` changes.

### 8. Conformance

Under [RFC 0004](0004-conformance-profiles.md), rule 3, a new profile, _Environment admission_: the canonical encoding and the `environment-1` parts, over synthetic models.

A **bound profile** is a set of profiles and exactly one model version. "WVP for merges on system X" is offline verification of the package version, ledger verification, a gate-decision specification once one exists, environment admission, and the model `{ id, version, digest }` with its own vectors, named by digest. One version per profile, since RFC 0004 has no optional parts. An implementation or a licensed library declares the bound profiles it reproduces, with the corpus commit and the digest of the model's vectors. Where those are licensed, only their holders can check the claim; the public report states the format profile alone.

## What a third party can verify offline

With the contract, the disclosure and its registry:

| Verifiable                                                                             | Not verifiable                                                    |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| The model version and interested set the contract was approved with                    | That the model's writers are true of the system                   |
| That each disclosed part is the model's, and its only definition at that path          | **That the licensed mapping read the system correctly**           |
| Who issued and signed each version, under its own keys                                 | That a completeness rule or an assumption holds                   |
| That the contract's kinds, types, keys and sources fit the model                       | Anything in an undisclosed part                                   |
| That every accepted source is authoritative for the contract under the model's writers | That no later version exists                                      |
| That a successor changed no used part; which assumptions a decision rests on           | That the contract is determinable, beyond an opaque report's word |

The second right-hand row is the source-accuracy boundary every WVP check has. A signed record shows who said it, not that it is true; a model shows what its issuer says the system is. A wrong mapping produces wrong records that verify, and nothing here detects that from a package. A model adds accountability: its digest commits to the connector, so its holder can later show what it did.

## RFC 0014's open question 1: system models offline

RFC 0014 left two options: (a) the parts a decision depends on travel with the package; (b) relying parties get free, verify-only read access to the model version. This RFC specifies (a), which makes (b) unnecessary **for verification**: everything admission and recomputation read is in the disclosure, checked against a head the contract pins.

| Left open by (a)                                                    | Left open by (b)                                                                                  |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Withheld parts stay unknown to the verifier                         | Verification depends on the publisher's availability and terms, for as long as decisions are kept |
| A package shows the version it used, not whether a newer one exists | The publisher learns who verifies which decisions, and when                                       |
| The head reveals paths and number of withheld parts                 | Every verifier sees more than any decision needs                                                  |
| Neither shows that the mapping was right                            | Neither shows that the mapping was right                                                          |

(b) stays useful, as an arrangement between parties, for what verification does not need: reviewing a model and auditing a mapping.

## Outcomes that change

None. `environment-1` is a new identifier in a new directory with its own vectors ([RFC 0001](0001-standards-process.md), invariant 2). A bound contract is a valid Language 1 or 2 contract that evaluates as it would without this specification.

New refusal codes: those of section 7.

## Compatibility

- **Inline kinds** stay valid, and the reference is optional: a contract without the parameter is what it is today. With it, inline kinds remain what evaluation reads; the model constrains them to a subset of its fields, with identical types, keyed by identity. Adopting a model renames kinds and sources: a new contract, approved again.
- **Language 1** raises `C_UNUSED` for the parameter; the parties answer that it binds the model.
- **Producers** name sources and kinds qualified, and project records onto the contract's fields, since evaluation refuses an undeclared one. A gateway serving two models signs under two source names.
- **Relying parties** register model issuers under `environment-model`, for endorsements and successors.
- **RFC 0014**'s `system-model` reference names an `environment-1` head. **RFC 0013**'s groups are what `per` names. Neither changes.

## Vectors

In `test-vectors/environment/v1`, over synthetic models of a ticket system, an invoice system and a landscape of both, at least:

- **Admitted:** model-bound kinds only; mixed with inline-only kinds; a contract over two components; one field authoritative under one binding and refused under another; a decision assigned to an interested role; a successor whose connector changed; `neverClosed` and `outOfModel`.
- **Refused,** every code, and: RFC 0008's vectors 282 and 283 under a model whose payment identity is its identifier (282 admitted, 283 `KEY_NOT_IDENTITY`); a key finer than the identity; a field the assignee can write; a copied field listing the payer; a part swapped under its path; a successor that changed an assumption, or is unendorsed; a diamond reaching two versions of one model.
- **Sufficiency:** each admitted case gives one result from its disclosure and from the whole model.
- **Order:** steps 8 and 10 failing at once, and 10 and 12.

## Security considerations

This RFC touches signing inputs, digests, the trust registry and what a result may be relied on for (RFC 0001, section 9.1). **The adversary** controls every byte of a package and its disclosure, and may be the model issuer. **Assumed:** Ed25519 and SHA-256 hold; the relying party's registry and pins are what it intends.

**Prevented:**

- _A model swapped under a contract._ The contract pins the binding, the binding the model. A successor needs the contract's consent, the issuer's signature and unchanged used parts.
- _A part swapped, or shown differently to two verifiers._ A part counts only under its head's digest, at a path that appears once.
- _Accepting a field the checked party can write_, once the model lists its role and the contract lists the role as interested.
- _Two items counted as one_ through a coarse key.
- _A conflicting composition_ resolved differently by two verifiers.

**Not prevented:**

- _A malicious or wrong model._ A model that omits a writer makes a claim look authoritative, and the verifier applies it faithfully: a model is its issuer's word. A relying party should register only model issuers outside its contracts' interested sets, and read the used parts before approving; nothing here can check who an issuer is.
- _Undisclosed parts hiding a bad mapping._ The digest commits to the mapping; it does not show it is right.
- _A stale model._ A producer can use a version whose successor added a writer, and a package cannot show it is the latest. A ledger's `pin.set` can say which version is in force.
- _A wrong interested set,_ which the parties approve with the contract.
- _Linkability:_ a disclosure shows which kinds a contract reads.

**Primitives.** Ed25519 (RFC 8032, under RFC 0002, rule 1), SHA-256 (FIPS 180-4). None is new.

**Review.** No person other than the author has reviewed this RFC. Under RFC 0001, section 9.1, it cannot become Final until a competent reviewer has, and is named here.

## Formal semantics

Nothing is proved here. Worth proving in Lean, digests injective and signatures assumed:

1. _Sufficiency of disclosure._ Admission is a function of the contract, the binding, the heads on the path and the used parts, so disclosed parts with their proofs of inclusion give the whole model's result.
2. _Independence._ If a contract is admitted and the model's writers are correct, no field an interested role can write, other than an assigned decision, reaches a Language 1 requirement: the paper's independence result carried to the language, as strong as its premise.
3. _Successors._ A successor that passes step 6 gives the bound version's result.
4. _Composition._ Name resolution in an admitted landscape is a function, and no head reaches itself.
5. _Monotonicity._ Adding a role to `interested`, or removing one from `decides`, can only turn admission into refusal.

**Tested only:** encodings, signatures, limits. **Neither:** that a model is true of its system.

## Alternatives

- **Models inline in every contract**, as kinds are today. Each contract repeats an unchecked vocabulary, and writers and completeness rules have no place in the language.
- **No model.** Without writers per field there is no contract-relative authority.
- **A member in a new language version.** Cleaner than a parameter, and a new language for what needs no change of evaluation.
- **A public model registry.** One party would decide where models are found and trusted, against invariant 7, and its availability would condition verification.
- **Whole models public.** An open format does not need open content.
- **A Merkle tree over parts**, as `ledger-1` uses. A smaller head and hidden paths, but an ordinary tree's inclusion proof cannot show that no other part has the same path.

## Open questions

1. **The name.** `environment-1` sits beside Language 1's _environment_, the records a contract is evaluated against; `environment-model-1` avoids the clash. RFC 0014 says `system-model`.
2. **The parameter,** or a member in a future language; and whether `C_UNUSED` should be silent for it.
3. **Large models.** Thousands of parts make a head of hundreds of kilobytes. A tree keyed by path would shrink it and hide withheld paths.
4. **Valid time.** The paper interprets each observation under the version valid when it was made. A package here uses one version.
5. **Out-of-model evidence:** whether a gate should fail on it, as drift.
6. **Identity across systems,** now an assumption; perhaps a structured link between components' kinds.
7. **Derived kinds** list provenance writers by hand; the paper computes them.
8. **`decides` and the actor:** refuse, rather than report, a decision assigned to the role whose work is checked.
9. **A public summary of a determinability report,** stating the expected share of undecided results.
10. **Limits.** Proposed: 4,096 parts per head, 64 KiB per interface part, 16 components, 4 levels.

## Decision

Not made. The review period of RFC 0001, section 5, has not started. This RFC will be accepted on the maintainers' judgement alone only if it says that it had no outside review (section 7.4).

## Implementation

Not implemented.

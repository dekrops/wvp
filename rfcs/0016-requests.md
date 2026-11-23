# RFC 0016: Requests

|            |                                                                                                                             |
| ---------- | --------------------------------------------------------------------------------------------------------------------------- |
| RFC        | 0016                                                                                                                        |
| Status     | Draft                                                                                                                       |
| Author     | Srishti                                                                                                                     |
| Created    | 2026-11-20                                                                                                                  |
| Affects    | New: `request-1` and `decision-explanation-1`, and the `ledger-1` extension identifier `request`. Nothing existing changes. |
| Supersedes | Nothing                                                                                                                     |

A new specification, `request-1`: how any agent asks before it acts, how the question is decided, and how the answer says why. A **request** is the question and nothing else: a contract, and the complete action the asker wants to take. A **decider** builds the package from that question, decides it, and records the decision in a `ledger-1` ledger ([RFC 0014](0014-ledger-v1.md)) before anyone sees it, with an **explanation** per requirement that a program can act on. What a system does with the answer, a **gate**, is [RFC 0018](https://github.com/dekrops/wvp/pull/60): it reads the requests, decisions and explanations defined here. Nothing here names a system: an action is an opaque call, and what a call holds for a given system belongs to that system's model ([RFC 0015](https://github.com/dekrops/wvp/pull/58)). This RFC proposes the design for review and does not publish it.

## Motivation

WVP verifies work after it is done. Agents increasingly need a check **before** they act: merge this, deploy that, pay this invoice. Each such check today invents its own way to ask, and nothing open says what a question is, who builds the evidence for it, or what the answer tells the asker.

| #   | Need                                                                     | Missing today                                                   |
| --- | ------------------------------------------------------------------------ | --------------------------------------------------------------- |
| R1  | One way to ask, for any agent and any system                             | Each check has its own request shape, or none                   |
| R2  | The asker can't choose the evidence, the cutoff, or see the answer first | Whoever writes the package chooses what counts                  |
| R3  | A decision answers exactly one action                                    | A decision names a digest that nothing ties to the action taken |
| R4  | An asker that is held learns what is missing, in a form a program reads  | A decision is one of three values                               |
| R5  | RFC 0014's `request` reference has a form                                | It is "SHA-256 of its canonical form", with no form defined     |

Enforcing the answer at the system of record is RFC 0018's. This RFC is what a gate, or anyone else, asks with and reads.

**Prior art.** Counterplay, the reference, has this design in its accepted RFC 0005: the question is in the record, and the decider builds the package. Its gate rules (its RFCs 0003 and 0007) are restated by RFC 0018. They are not public and are written against Counterplay's ledger. This RFC restates the request side in this family's encodings, on `ledger-1`, without Counterplay's or any system's names, and adds a nonce to the request.

## What changes

A new specification, `request-1`, in the family's encodings with [RFC 0002](0002-inputs-every-verifier-refuses-alike.md) applied from the start: `verified-json-v1`, digests as `{ "algorithm": "sha-256", "hex" }`, Ed25519 signatures as `{ "scheme", "keyId", "encoded" }`, canonical instants. It includes `decision-explanation-1` (section 5).

_Askers_ write requests: an agent's harness, or better, a gate describing what its system was asked to apply (RFC 0018). The _decider_ builds packages, records decisions and writes explanations, with a service key whose `kinds` include `decision.recorded`.

### 1. A request: the question, and nothing else

```json
{
  "request": {
    "protocol": "request-1",
    "ledger": { "algorithm": "sha-256", "hex": "…" },
    "contract": {
      "kind": "contract",
      "digest": { "algorithm": "sha-256", "hex": "…" }
    },
    "action": {
      "name": "merge",
      "call": {
        "repository": "example/shop",
        "target": "main",
        "base": "77ab01d3",
        "revision": "4f2c9e1b",
        "change": "42"
      }
    },
    "askedAt": "2026-11-20T10:00:00Z",
    "nonce": "kq3Yb4mXGm1sV9cS0p2a0Q=="
  },
  "signature": { "scheme": "Ed25519", "keyId": "…", "encoded": "…" }
}
```

- **`ledger`** is the genesis digest of the ledger the decision will be recorded in, so a request is never answered in another tenant's ledger.
- **`contract`** is the contract the question is asked under, as RFC 0014's reference.
- **`action.name`** matches Language 1's name pattern. **`action.call`** is the **complete** call: everything that makes this action this action, whether the contract reads it or not. Two calls that differ in anything, such as the same change merged into another target, are different actions.
- **`in`**, optional: for an action that is one member of a combined state (a merge queue's commit, a payment run), the hex SHA-256 of the canonical text of the combined state's identifier, as the system names it. RFC 0018 says when a gate sets it.
- **`askedAt`** is when the asker says it asked. It bounds the decider's cutoff (section 3) and is otherwise the asker's word.
- **`nonce`** is the base64 of 16 random octets, so a request's digest discloses nothing of a guessable call.
- The **request digest** is SHA-256 of the canonical `request` member: RFC 0014's `request` reference. The **action digest** is SHA-256 of the canonical `action` member.
- The signature is over `verified:request:v1\n` and the canonical `request` member, by a key the relying party's registry holds for the asker.

A request holds no evidence, no inputs and no cutoff: the asker chooses none of them.

**Asking again is a new request.** The same action asked twice has one action digest and two request digests, by their nonces. Each gets its own decision (section 4), and the ledger shows both. This is how a request left `UNDETERMINED` is asked again once the missing evidence has arrived.

### 2. The projection: from a call to the contract's inputs and the subject

A contract's inputs are a **projection** of the call, never written by the asker. A projection says, for one contract and one action name, how each input is read from the call, which evidence is relevant, and what the action is about:

```json
{
  "projection": {
    "protocol": "request-1",
    "contract": {
      "kind": "contract",
      "digest": { "algorithm": "sha-256", "hex": "…" }
    },
    "action": "merge",
    "inputs": { "change": "/change", "revision": "/revision" },
    "select": { "review": { "change": "change" } },
    "subject": { "item": "/change", "state": ["/revision", "/base"] }
  }
}
```

- **`inputs`** maps every input of the contract except its cutoff input to a JSON Pointer (RFC 6901) into `action.call`. The value found must fit the input's declared type. A request whose call has no value there, or one of another type, is refused before anything is decided (`NOT_PROJECTABLE`).
- **`select`** maps a kind to field-equals-input conditions. A record of that kind is relevant only if each named field equals the named input. A kind with no entry takes every record of it.
- **`subject`** names, as JSON Pointers into `action.call`, the **item** acted on and the members that make up its exact **state**: for a merge, the revision and the base it lands on. A call missing one is `NOT_PROJECTABLE`.
- **Pinned by the ledger.** Approvers pin a contract's projection with `pin.set` (RFC 0014), under the name `request/<contract id>`, at the threshold, as a reference of a new kind, `projection`: SHA-256 of the canonical `projection` member. Moving it is a trust entry, so every decision signed against the old basis goes stale.

**The subject** of a request is RFC 0014's `subject`, what is decided:

```json
{ "item": "42", "state": "9f2c…", "in": "…" }
```

- **`item`** is the value at the projection's `item` pointer, as a string, at most 64 octets.
- **`state`** is the hex SHA-256 of the canonical array of the values at the `state` pointers, in the projection's order. Any change to what the action would apply is a new state.
- **`in`** is the request's `in`, when it has one.

The request digest commits to the call and the ledger pins the projection, so a request's subject is fixed by the request and the basis: nobody can give one request two subjects. Two requests with one subject are about the same thing in the same state. RFC 0018 reads the latest of them, and salts the subject before anything about it enters the ledger.

### 3. The decider builds the package

For a request, the decider builds a package (WVP v0.2) whose:

- **`contract`** is the one the request names;
- **`inputs`** are the projection of `action.call`, plus the cutoff input, when the contract names one, set to the decider's clock (below);
- **`evidence`** is a deterministic selection from the statements the decider holds, those that:

  - are for the ledger's tenant, and signed by a key the decider's registry holds for the source they name, of a kind the contract declares (recomputation checks the same against the relying party's registry);
  - were observed no later than the cutoff;
  - for a record, match the projection's `select`;
  - for a completeness statement, cover what the package's records are drawn from: the whole kind, or with [RFC 0013](https://github.com/dekrops/wvp/pull/56), the group the `select` names;

  in ascending order of statement identifier. More than the language's limit of facts is refused (`SELECTION_TOO_LARGE`): the projection needs a narrower `select`.

The request and the projection travel with the package, beside it as RFC 0015's disclosure does, so recomputation can check that the package answers this question. A later package version may make them components.

**The cutoff is the decider's clock**, read once: it is the time of the decision, and the **cutoff of the request** it answers. The decider never decides before the request (a request whose `askedAt` is ahead of its clock is refused, `NOT_YET`), and refuses one more than a set **skew** behind it (`TOO_OLD`), as a stale question to be asked again. So the cutoff lies in [`askedAt`, `askedAt` + skew]. An asker can't move it backwards to leave out a record observed since it asked. Among requests about one subject, the cutoff orders them: RFC 0018's current request is the one with the latest.

So the package is a function of the request, the projection pinned in the ledger, and the decider's statements: two deciders holding the same statements build the same package.

### 4. The decision is recorded before it is disclosed

Deciding is one operation: build the package, evaluate it, write the explanation (section 5), append `decision.recorded` (RFC 0014) with `request` set to the request digest and `explanation` to the explanation's reference, and only then answer, reading the answer back from the appended entry. If the append fails, there is no answer, and a gate has nothing to act on.

So every question that was ever answered is in the ledger: an asker can't ask until it passes without the ledger showing each attempt. RFC 0014 allows one decision per request, which with section 1 means one answer per question asked, and a new question for every re-ask.

### 5. The explanation: `decision-explanation-1`

A decision is one of three values. An asker that is held needs to know which requirement didn't hold, and what would decide it. The decider writes that with the decision, because it is the one that evaluated the contract:

```json
{
  "protocol": "decision-explanation-1",
  "requirements": [
    { "id": "CHECKS_PASSED", "value": "TRUE" },
    {
      "id": "REVIEWED_BY_ANOTHER",
      "value": "UNKNOWN",
      "causes": [
        {
          "cause": "absent",
          "kind": "changes.review",
          "sources": ["changes.api"]
        }
      ]
    },
    {
      "id": "NO_WORKFLOW_CHANGE",
      "value": "FALSE",
      "by": [{ "algorithm": "sha-256", "hex": "…" }]
    }
  ]
}
```

- **`requirements`** has one member per requirement of the contract, in the contract's order: its `id` and its Language 1 `value`.
- A **`TRUE`** requirement has nothing else.
- A **`FALSE`** requirement has **`by`**: the statement digests of the records that make it `FALSE`, ascending, at most 16.
- An **`UNKNOWN`** requirement has **`causes`**, collected where evaluation reached `UNKNOWN`, as a set in ascending order of canonical text, from a closed list:

| Cause           | When ([Language 1](../protocols/work-contract/v1/SPEC.md), section 7)    | Names                      | What would decide it                      |
| --------------- | ------------------------------------------------------------------------ | -------------------------- | ----------------------------------------- |
| `absent`        | An `exists` found no record making it `TRUE`, and its kind is not closed | `kind`, accepted `sources` | A record that satisfies it, or a listing  |
| `not-closed`    | A `forall` found no counterexample, and its kind is not closed           | `kind`, accepted `sources` | A completeness statement as of the cutoff |
| `missing-field` | A comparison read an absent optional field                               | `kind`, `field`, `record`  | The field                                 |
| `conflict`      | The kind is open because accepted records with one key disagree          | `kind`, `records`          | A corrected record                        |

Kinds and sources are the contract's names: for a contract bound to a system model, the model's qualified names (`changes.review`, `changes.api`), never a gate's or an agent's. An asker acts on them: `by` names the records to change, `absent` the kind of record to obtain, `not-closed` the listing to ask the source for.

**Committed with the decision.** The explanation's digest is SHA-256 of its canonical object, a reference of a new kind, `explanation`, which the decider names as `decision.recorded`'s `explanation`. It is a function of the contract and the package, so recomputation checks it as it checks the decision (step 8). It is kept with the package, never in the ledger. A gate copies it into its receipt (RFC 0018) and never writes one.

**Not only for gates.** An auditor reading a ledger learns from the explanations why each decision was undecided, and what evidence each was waiting for, without the gate or the asker.

## The verification algorithm

**Recomputation** of a decision whose package, request and projection are given. Checks run in this order and stop at the first failure:

| Step | Check                                                                                                                      | Result if it fails      |
| ---- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| 1    | The request is well formed and its signature counts; its digest is the decision's `request`                                | `REQUEST_MISMATCH`      |
| 2    | The request names the decision's ledger and contract, and the package's contract has that digest                           | `CONTRACT_MISMATCH`     |
| 3    | The projection is the one pinned for the contract at the decision's basis, for the request's action name                   | `PROJECTION_MISMATCH`   |
| 4    | The decision's time is within [`askedAt`, `askedAt` + skew], the skew being the relying party's setting (open question 2)  | `OUT_OF_SKEW`           |
| 5    | The package's inputs are the projection of the call, plus the decision's time as the cutoff                                | `INPUTS_MISMATCH`       |
| 6    | The package's evidence is the selection of section 3 from its own statements                                               | `EVIDENCE_NOT_SELECTED` |
| 7    | The package decides as the entry says                                                                                      | `DISAGREES`             |
| 8    | When the entry names an explanation: the given explanation has that digest, and is the one section 5 gives for the package | `EXPLANATION_MISMATCH`  |

Steps 1 to 5 run before any evidence is admitted, so an admission refusal can't hide a package made for another question. Step 6 checks that nothing in the package should have been left out of it. Whether the decider held a statement it didn't include needs its store, and is a matter of completeness statements, as everywhere in WVP.

The report states `recomputed`: `AGREES`, a failing step, or `NOT_RECOMPUTABLE` without the package. What gates did with decisions is checked by RFC 0018.

## Outcomes that change

None. `request-1` is a new identifier in a new directory with its own vectors (RFC 0001, invariant 2). It uses `ledger-1`'s `decision.recorded` and `pin.set` as defined there. It adds two reference kinds, `projection` and `explanation`, and no entry kind.

The identifier `request` is assigned in [the registry of ledger extensions](../governance/ledger-extensions.md), for the pin names `request/…`, and for entry kinds a later version may need (open questions 6 and 7).

New result codes: `NOT_PROJECTABLE`, `SELECTION_TOO_LARGE`, `NOT_YET`, `TOO_OLD`, `REQUEST_MISMATCH`, `CONTRACT_MISMATCH`, `PROJECTION_MISMATCH`, `OUT_OF_SKEW`, `INPUTS_MISMATCH`, `EVIDENCE_NOT_SELECTED`, `DISAGREES`, `EXPLANATION_MISMATCH`.

## Compatibility

- **RFC 0014:** its `request` reference is a `request-1` request, and its `subject` is section 2's. Its draft's own request form, with `cutoff` and `evidence` in the request, is replaced by a reference to this RFC: here the decider chooses both, and the cutoff is the decision's time. This RFC adds the reference kinds `projection` and `explanation`, as RFC 0014 lets other specifications do. Nothing else in `ledger-1` changes.
- **RFC 0015:** what a system's call holds is the system's business, so a model could describe it, for example as an interface part `action/<name>` listing the call's members, its item and its state. This RFC needs no such part; an open question below.
- **RFC 0018:** a gate describes the pending action as a request, reads the decision of the current request about its subject, and copies the explanation into its receipt. Its configuration names which actions and contracts it guards; this RFC says how each is asked and answered.
- **Counterplay:** its request maps onto `request-1` with a nonce added, its binding onto the projection, and its decision's gaps onto the explanation. Its `gate.acted` maps onto RFC 0018's `gate/acted`. Its own ledgers stay in its format; a `ledger-1` ledger starts from a new genesis (RFC 0014).
- **Naming:** this RFC says _projection_ for what Counterplay calls a binding, since RFC 0015's binding is a contract's pinned model.

## Vectors

In `test-vectors/request/v1`, synthetic, with public test keys, at least:

- **Requests:** one per action shape; the same action asked twice (two request digests, one action digest); a call missing a projected member, or with one of another type (`NOT_PROJECTABLE`); a member of a combined state, with `in`.
- **Subjects:** two calls differing only in a member outside `subject` (one subject, two actions); a changed base (a new state); a call missing the item or a state member (`NOT_PROJECTABLE`).
- **Assembly:** the same request, projection and statements give the same package; a statement after the cutoff, outside the `select`, of an undeclared kind, or from an unregistered key, is left out; a selection over the limit is refused; a group completeness statement for the `select`'s value is kept.
- **Explanations:** each cause, alone and together; a `FALSE` requirement with its `by`; a requirement `UNKNOWN` for two causes.
- **Recomputation:** one package that agrees, and one per failing step: another request, another contract, a projection not the pinned one, a decision before `askedAt` or beyond the skew, an input changed, a selected record removed or an unselected one added, a different decision, an explanation with a cause changed.

## Security considerations

This RFC touches signing inputs, digests, time and what a result may be relied on for (RFC 0001, section 9.1). **The adversary** may be the asker or the agent: it chooses what to ask and when, and may control what its harness sends. **Assumed:** the signature scheme and SHA-256 hold; the decider is not the agent's.

**Prevented,** for an asker that is not the decider:

- choosing which evidence counts, or leaving a record out;
- choosing the cutoff, or moving it before the question;
- seeing a decision before it is recorded;
- asking until a request passes without the ledger showing each attempt;
- a decision answering an action other than the one asked about, or a subject other than the request's;
- an explanation the decider didn't compute from the package going unnoticed by a third party (step 8).

**Not prevented:**

- **A decider run by the actor.** Whoever runs the decider builds the package, and could compute a decision offline before recording it. Recording before disclosure holds where the decider is independent. Who runs it is a deployment's choice, and this RFC makes it the place that matters.
- **What the decider holds.** It selects from the statements it has. A source that never reported, or a store that lost a record, gives a smaller package. Completeness statements are what show a set is whole.
- **The decider's clock,** within [`askedAt`, `askedAt` + skew], until checkpoints are witnessed (RFC 0014).
- **When the asker asks.** It can wait for a favourable record, or ask just before an unfavourable one lands. It can't reach back before its question.
- **An action taken without a request.** It leaves no entry. RFC 0018's gate at the system of record closes that for the systems that have one; audits close the rest.
- **A request asked by the agent, not the system.** An agent's harness describes what the agent says it will do. A gate describing what the system was asked to apply is better evidence (RFC 0018).
- **What an explanation discloses.** It names kinds, sources and record digests. Whoever receives it learns which evidence was missing or contrary; a deployment that answers an agent shares that much with it.
- **Linkability.** A decision names a request digest, which its nonce hides. But whoever holds two requests for one action sees they are one action.

## Formal semantics

Nothing is proved with this RFC. Worth proving in Lean, digests injective and signatures assumed:

1. **Assembly** is a function of the request, the pinned projection and the statements.
2. **Projection** reads only the call: two requests with one action and one projection get the same inputs and the same subject.
3. **One action per decision.** A decision's request has one action digest, and one subject under its basis.
4. **Explanation soundness.** Each `by` record is in the package and makes its requirement `FALSE`; each cause names a kind the evaluation found open, or a field it found absent; and the explanation's values are the requirements' values in the decision.

**Tested only:** encodings, signatures, the selection's order. **Neither:** that the system applied what was asked. That is the system's own record, which a contract can read as evidence afterwards.

## Alternatives

- **The asker builds and signs the package.** A signature binds the asker to its choice; it doesn't stop the choice.
- **The contract's inputs as the action.** Then two calls that agree on the inputs share a decision, and a gate could use one decision for both: the same change merged into two targets.
- **The cutoff in the request, bounded by the decider's clock** (RFC 0014's draft form). It still lets the asker pick a moment inside the bound, which is the choice this design takes away.
- **The subject written by the asker.** Then an asker could name one state and call for another. Read through the pinned projection, it follows from the call.
- **A `request.recorded` entry** before each decision, as Counterplay's `claim.recorded`. It would also show requests never answered. But every answered request is already in the ledger through its decision, and RFC 0014 leaves this kind out.
- **The explanation defined with the gate** (RFC 0018's first draft). The decider computes it, recomputation checks it, and an auditor needs it without any gate, so it belongs with the decision.

## Open questions

1. **Action schemas in system models.** Should RFC 0015 define an `action/<name>` part, with the call's members, its item and its state, so a projection can be checked against what a system's call actually holds?
2. **The skew.** One value for every deployment, a member of the pinned projection, or the relying party's choice?
3. **Several deciders.** Should a ledger name which decider key decides which contract? RFC 0018's configuration names its deciders per gate.
4. **Richer selection.** `select` matches fields to inputs by equality. Ranges ("reversals in the last quarter") or references to another kind may be needed.
5. **The agent as a party.** A call may name the agent and whom it acts for, but nothing here checks it. Agent identity and delegation need their own RFC.
6. **Holds across requests.** Two requests for one invoice's payment get two valid decisions. Counterplay's settlement permits hold a key across requests; that state could be a later extension `request/…`.
7. **Unanswered requests.** Is it worth recording a request before its decision, to show the ones never answered?
8. **Causes for Language 2.** The causes are those of Language 1. With [RFC 0008](https://github.com/dekrops/wvp/pull/47), an aggregate over an open kind is `not-closed` of that kind. [RFC 0009](https://github.com/dekrops/wvp/pull/52) (an interval on both sides of a bound), [RFC 0012](https://github.com/dekrops/wvp/pull/55) (`NOT_APPLICABLE`) and RFC 0013 (one group not closed) may each need a cause or a value of their own.
9. **Which records `by` names.** A requirement can be `FALSE` for many records. The exact rule choosing the 16, so that two deciders write one explanation, is not yet fixed.
10. **The explanation as its own specification.** It is useful beyond requests, for audits of any decision. Kept here while one specification uses it.

## Decision

Not made. The review period of RFC 0001, section 5, has not started.

## Implementation

Not implemented. Counterplay implements the design this restates, in its own formats.

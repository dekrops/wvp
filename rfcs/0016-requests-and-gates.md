# RFC 0016: Requests and gates

|            |                                             |
| ---------- | ------------------------------------------- |
| RFC        | 0016                                        |
| Status     | Draft                                       |
| Author     | Srishti                                     |
| Created    | 2026-11-20                                  |
| Affects    | New: `request-1`. Nothing existing changes. |
| Supersedes | Nothing                                     |

A new specification, `request-1`: how any agent asks before it acts, and how the system it acts on enforces the answer. A **request** is the question and nothing else: a contract, and the complete action the asker wants to take. A **decider** builds the package from that question, decides it, and records the decision in a `ledger-1` ledger ([RFC 0014](0014-ledger-v1.md)) before anyone sees it. A **gate** at the system of record acts only on a recorded decision for exactly that action, and records what it did. Nothing here names a system: an action is an opaque call, and what a call holds for a given system belongs to that system's model ([RFC 0015](https://github.com/dekrops/wvp/pull/58)). This RFC proposes the design for review and does not publish it.

## Motivation

WVP verifies work after it is done. Agents increasingly need a check **before** they act: merge this, deploy that, pay this invoice. Each such gate today invents its own way to ask, and nothing open says what a question is, who builds the evidence for it, or how a third party checks that the gate acted on the answer.

| #   | Need                                                                     | Missing today                                                   |
| --- | ------------------------------------------------------------------------ | --------------------------------------------------------------- |
| R1  | One way to ask, for any agent and any system                             | Each gate has its own request shape, or none                    |
| R2  | The asker can't choose the evidence, the cutoff, or see the answer first | Whoever writes the package chooses what counts                  |
| R3  | A decision answers exactly one action                                    | A decision names a digest that nothing ties to the action taken |
| R4  | A third party can check that a gate let through only what was supported  | Gate actions aren't recorded in an open format                  |
| R5  | RFC 0014's `request` reference has a form                                | It is "SHA-256 of its canonical form", with no form defined     |

**Prior art.** Counterplay, the reference, has this design in three accepted RFCs: a gate allows only on `SUPPORTED` (its RFC 0003), the question in the record and the decider builds the package (its RFC 0005), and a neutral gate interface (its RFC 0007). They are not public and are written against Counterplay's ledger. This RFC restates them in this family's encodings, on `ledger-1`, without Counterplay's or any system's names, and adds a nonce to the request.

## What changes

A new specification, `request-1`, in the family's encodings with [RFC 0002](0002-inputs-every-verifier-refuses-alike.md) applied from the start: `verified-json-v1`, digests as `{ "algorithm": "sha-256", "hex" }`, Ed25519 signatures as `{ "scheme", "keyId", "encoded" }`, canonical instants.

_Askers_ write requests: an agent's harness, or better, a gate describing what its system was asked to apply (section 5). The _decider_ builds packages and records decisions, with a service key whose `kinds` include `decision.recorded`. A _gate_ enforces, with a service key whose `kinds` include `request-1/gate.acted`.

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
- **`askedAt`** is when the asker says it asked. It bounds the decider's cutoff (section 3) and is otherwise the asker's word.
- **`nonce`** is the base64 of 16 random octets, so a request's digest discloses nothing of a guessable call.
- The **request digest** is SHA-256 of the canonical `request` member: RFC 0014's `request` reference. The **action digest** is SHA-256 of the canonical `action` member.
- The signature is over `verified:request:v1\n` and the canonical `request` member, by a key the relying party's registry holds for the asker.

A request holds no evidence, no inputs and no cutoff: the asker chooses none of them.

**Asking again is a new request.** The same action asked twice has one action digest and two request digests, by their nonces. Each gets its own decision (section 4), and the ledger shows both. This is how a request left `UNDETERMINED` is asked again once the missing evidence has arrived.

### 2. The projection: from a call to the contract's inputs

A contract's inputs are a **projection** of the call, never written by the asker. A projection says, for one contract and one action name, how each input is read from the call, and which evidence is relevant:

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
    "select": { "review": { "change": "change" } }
  }
}
```

- **`inputs`** maps every input of the contract except its cutoff input to a JSON Pointer (RFC 6901) into `action.call`. The value found must fit the input's declared type. A request whose call has no value there, or one of another type, is refused before anything is decided (`NOT_PROJECTABLE`).
- **`select`** maps a kind to field-equals-input conditions. A record of that kind is relevant only if each named field equals the named input. A kind with no entry takes every record of it.
- **Pinned by the ledger.** Approvers pin a contract's projection with `pin.set` (RFC 0014), under the name `<contract id>.projection`, at the threshold, as a reference of a new kind, `projection`: SHA-256 of the canonical `projection` member. Moving it is a trust entry, so every decision signed against the old basis goes stale.

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

**The cutoff is the decider's clock**, read once: it is the time of the decision. The decider never decides before the request (a request whose `askedAt` is ahead of its clock is refused, `NOT_YET`), and refuses one more than a set **skew** behind it (`TOO_OLD`), as a stale question to be asked again. So the cutoff lies in [`askedAt`, `askedAt` + skew]. An asker can't move it backwards to leave out a record observed since it asked.

So the package is a function of the request, the projection pinned in the ledger, and the decider's statements: two deciders holding the same statements build the same package.

### 4. The decision is recorded before it is disclosed

Deciding is one operation: build the package, evaluate it, append `decision.recorded` (RFC 0014) with `request` set to the request digest, and only then answer, reading the answer back from the appended entry. If the append fails, there is no answer, and a gate has nothing to act on.

So every question that was ever answered is in the ledger: an asker can't ask until it passes without the ledger showing each attempt. RFC 0014 allows one decision per request, which with section 1 means one answer per question asked, and a new question for every re-ask.

### 5. Gates

A **gate** is an enforcement point at a system of record: the place where an action is applied or refused, whatever the agent did before. Enforcement stays there and not in the agent's harness: a harness can be removed, but the system's own check can't be skipped.

For each action its system is about to apply, a gate:

1. **Describes it** as a request, from the system's own event, not from what an agent said it would do. What the system was actually asked to apply is better evidence than an agent's intention.
2. **Asks,** and waits for the decision on that request, read from the ledger.
3. **Acts** on a decision that names this request, is not stale, and whose request has the action digest of what the system is about to apply:

   | Mode        | Decision                                   | The system | Outcome          |
   | ----------- | ------------------------------------------ | ---------- | ---------------- |
   | `enforcing` | `SUPPORTED`                                | applies it | `allowed`        |
   | `enforcing` | `UNDETERMINED`, with a `decision.override` | applies it | `overridden`     |
   | `enforcing` | anything else                              | refuses it | `refused`        |
   | `shadow`    | any                                        | applies it | `observed`       |
   | `enforcing` | none in time, or stale                     | refuses it | nothing recorded |

4. **Says why,** in the system's own way: the contract, the requirements that didn't hold, and what was missing.
5. **Records what it did** as a `request-1/gate.acted` entry (section 6).

**Fail closed.** In `enforcing`, a gate that gets no fresh decision in time, or can't reach the ledger, refuses. A missing or unreadable configuration never means `shadow`.

### 6. `gate.acted`, an extension kind of `ledger-1`

| Kind                   | Body                                                                                                                           | Signed by            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------------- |
| `request-1/gate.acted` | `decision` (entry digest), `outcome` (`allowed`, `overridden`, `refused`, `observed`), `effect` (a label naming the mechanism) | A gate's service key |

As an extension kind (RFC 0014, section 5), it is a record entry: it never moves the basis, and a `ledger-1` verifier lists it `UNINTERPRETED`. A `request-1` verifier checks these rules and reports its result beside the ledger's:

| Outcome      | Holds when                                                                            |
| ------------ | ------------------------------------------------------------------------------------- |
| `allowed`    | The decision is `SUPPORTED`, under `enforcing`                                        |
| `overridden` | The decision is `UNDETERMINED`, under `enforcing`, and a `decision.override` names it |
| `observed`   | The decision's contract is in `shadow`                                                |
| `refused`    | Always: a gate may be stricter than a contract                                        |

and in every case: the entry's basis is the decision's (so a trust change in between makes it stale), and **no other `gate.acted` names the same decision**. A gate refused once and asked again needs a new request.

So from the ledger alone, a third party counts what was allowed, overridden, refused and only observed, and checks that every action let through had a `SUPPORTED` decision or a recorded override behind it.

## The verification algorithm

**Recomputation** of a decision whose package, request and projection are given. Checks run in this order and stop at the first failure:

| Step | Check                                                                                                                     | Result if it fails      |
| ---- | ------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| 1    | The request is well formed and its signature counts; its digest is the decision's `request`                               | `REQUEST_MISMATCH`      |
| 2    | The request names the decision's ledger and contract, and the package's contract has that digest                          | `CONTRACT_MISMATCH`     |
| 3    | The projection is the one pinned for the contract at the decision's basis, for the request's action name                  | `PROJECTION_MISMATCH`   |
| 4    | The decision's time is within [`askedAt`, `askedAt` + skew], the skew being the relying party's setting (open question 2) | `OUT_OF_SKEW`           |
| 5    | The package's inputs are the projection of the call, plus the decision's time as the cutoff                               | `INPUTS_MISMATCH`       |
| 6    | The package's evidence is the selection of section 3 from its own statements                                              | `EVIDENCE_NOT_SELECTED` |
| 7    | The package decides as the entry says                                                                                     | `DISAGREES`             |

Steps 1 to 5 run before any evidence is admitted, so an admission refusal can't hide a package made for another question. Step 6 checks that nothing in the package should have been left out of it. Whether the decider held a statement it didn't include needs its store, and is a matter of completeness statements, as everywhere in WVP.

**Gate acts** are checked by the rules of section 6, from the ledger alone.

The report states apart: `recomputed` (`AGREES`, a failing step, or `NOT_RECOMPUTABLE` without the package), and for gate acts, `gateValid` and the counts per outcome.

## Outcomes that change

None. `request-1` is a new identifier in a new directory with its own vectors (RFC 0001, invariant 2). It uses `ledger-1`'s `decision.recorded`, `decision.override` and `pin.set` as defined there, and adds one extension kind.

New result codes: `NOT_PROJECTABLE`, `SELECTION_TOO_LARGE`, `NOT_YET`, `TOO_OLD`, `REQUEST_MISMATCH`, `CONTRACT_MISMATCH`, `PROJECTION_MISMATCH`, `OUT_OF_SKEW`, `INPUTS_MISMATCH`, `EVIDENCE_NOT_SELECTED`, `DISAGREES`.

## Compatibility

- **RFC 0014:** its `request` reference now has a form, the request digest, and this RFC adds the reference kind `projection`, as RFC 0014 lets other specifications do. Nothing else in `ledger-1` changes.
- **RFC 0015:** what a system's call holds is the system's business, so a model could describe it, for example as an interface part `action/<name>` listing the call's members. This RFC needs no such part; an open question below.
- **Counterplay:** its request maps onto `request-1` with a nonce added, its binding onto the projection, and its `gate.acted` onto the extension kind. Its own ledgers stay in its format; a `ledger-1` ledger starts from a new genesis (RFC 0014).
- **Naming:** this RFC says _projection_ for what Counterplay calls a binding, since RFC 0015's binding is a contract's pinned model.

## Vectors

In `test-vectors/request/v1`, synthetic, with public test keys, at least:

- **Requests:** one per action shape; the same action asked twice (two request digests, one action digest); a call missing a projected member, or with one of another type (`NOT_PROJECTABLE`).
- **Assembly:** the same request, projection and statements give the same package; a statement after the cutoff, outside the `select`, of an undeclared kind, or from an unregistered key, is left out; a selection over the limit is refused; a group completeness statement for the `select`'s value is kept.
- **Recomputation:** one package that agrees, and one per failing step: another request, another contract, a projection not the pinned one, a decision before `askedAt` or beyond the skew, an input changed, a selected record removed or an unselected one added, a different decision.
- **Gate acts:** `allowed` on `SUPPORTED` and on `UNDETERMINED`; `overridden` with and without an override; `observed` under `enforcing`; `refused` on `SUPPORTED`; a second act on one decision; an act across a trust change.

## Security considerations

This RFC touches signing inputs, digests, time and what a result may be relied on for (RFC 0001, section 9.1). **The adversary** may be the asker or the agent: it chooses what to ask and when, and may control what its harness sends. **Assumed:** the signature scheme and SHA-256 hold; the decider and the gate are not the agent's.

**Prevented,** for an asker that is not the decider:

- choosing which evidence counts, or leaving a record out;
- choosing the cutoff, or moving it before the question;
- seeing a decision before it is recorded;
- asking until a request passes without the ledger showing each attempt;
- a decision used for an action other than the one asked about, or used twice;
- a gate's act on anything but a `SUPPORTED` decision or a recorded override going unnoticed by a third party.

**Not prevented:**

- **A decider run by the actor.** Whoever runs the decider builds the package, and could compute a decision offline before recording it. Recording before disclosure holds where the decider is independent. Who runs it is a deployment's choice, and this RFC makes it the place that matters.
- **What the decider holds.** It selects from the statements it has. A source that never reported, or a store that lost a record, gives a smaller package. Completeness statements are what show a set is whole.
- **The decider's clock,** within [`askedAt`, `askedAt` + skew], until checkpoints are witnessed (RFC 0014).
- **When the asker asks.** It can wait for a favourable record, or ask just before an unfavourable one lands. It can't reach back before its question.
- **An action taken without a request.** It leaves no entry. A gate at the system of record closes that for the systems that have one; audits close the rest.
- **Linkability.** A gate act names a decision, and a decision names a request digest, which its nonce hides. But whoever holds two requests for one action sees they are one action.

## Formal semantics

Nothing is proved with this RFC. Worth proving in Lean, digests injective and signatures assumed:

1. **Assembly** is a function of the request, the pinned projection and the statements.
2. **Projection** reads only the call: two requests with one action and one projection get the same inputs.
3. **Gate soundness.** In a ledger whose gate acts satisfy section 6, every `allowed` names a `SUPPORTED` decision and every `overridden` an overridden `UNDETERMINED` one, both under `enforcing` in the decision's basis, and no decision is acted on twice.
4. **No reuse.** A gate act's decision answers a request whose action digest is the act's.

**Tested only:** encodings, signatures, the selection's order. **Neither:** that the system applied what its gate allowed. That is the system's own record, which a contract can read as evidence afterwards.

## Alternatives

- **The asker builds and signs the package.** A signature binds the asker to its choice; it doesn't stop the choice.
- **The contract's inputs as the action.** Then two calls that agree on the inputs share a decision, and a gate could use one decision for both: the same change merged into two targets.
- **The cutoff in the request, bounded by the decider's clock.** It still lets the asker pick a moment inside the bound, which is the choice this design takes away.
- **A `request.recorded` entry** before each decision, as Counterplay's `claim.recorded`. It would also show requests never answered. But every answered request is already in the ledger through its decision, and RFC 0014 leaves this kind out.
- **Gate acts as a core kind of `ledger-1`.** Their rules would then make a ledger invalid. As an extension, a ledger stays verifiable by a verifier that knows no gates, and the gate rules are reported beside it.

## Open questions

1. **Action schemas in system models.** Should RFC 0015 define an `action/<name>` part, so a projection can be checked against what a system's call actually holds?
2. **The skew.** One value for every deployment, a member of the pinned projection, or the relying party's choice?
3. **Several deciders.** Should a ledger name which decider key decides which contract?
4. **Richer selection.** `select` matches fields to inputs by equality. Ranges ("reversals in the last quarter") or references to another kind may be needed.
5. **The agent as a party.** A call may name the agent and whom it acts for, but nothing here checks it. Agent identity and delegation need their own RFC.
6. **Holds across requests.** Two requests for one invoice's payment get two valid decisions. Counterplay's settlement permits hold a key across requests; that state could be a later extension of `request-1`.
7. **Unanswered requests.** Is it worth recording a request before its decision, to show the ones never answered?

## Decision

Not made. The review period of RFC 0001, section 5, has not started.

## Implementation

Not implemented. Counterplay implements the design this restates, in its own formats.

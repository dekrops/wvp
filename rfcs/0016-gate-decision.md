# RFC 0016: Gate decision

|            |                                                           |
| ---------- | --------------------------------------------------------- |
| RFC        | 0016                                                      |
| Status     | Draft                                                     |
| Author     | Zin Nam                                                   |
| Created    | 2026-11-23                                                |
| Affects    | New: ledger-1 extension `gate`. Nothing existing changes. |
| Supersedes | Nothing                                                   |

A new specification, `gate-1`, registered as the `ledger-1` extension `gate`: what a **gate** does with the decisions a ledger records, and how anyone checks afterwards that it did it. A gate guards one action on one system: a merge, a payment release, a deployment. It reads decisions and never makes them. It records each action it let proceed or held in one entry, `gate/acted`, and answers the requester with a signed receipt a program can act on. This RFC proposes the design for review, stacked on [RFC 0014](0014-ledger-v1.md). It does not publish `gate-1`.

## Motivation

RFC 0014 keeps what a gate did out of the core: "the ledger shows what was decided, not what a gate did". Its section 5 leaves that to this extension.

| #   | Need                                                               | Missing in `ledger-1` alone                   |
| --- | ------------------------------------------------------------------ | --------------------------------------------- |
| G1  | Show that an action proceeded only on a `SUPPORTED` decision       | No entry records an action                    |
| G2  | Show that a `decision.override` let one request proceed, once      | An override is recorded; its use is not       |
| G3  | A decision about one state never authorizes another                | Nothing ties an action to a request's subject |
| G4  | A held requester learns what is missing, in a form a program reads | A decision is one of three values             |
| G5  | Many actions per second                                            | RFC 0014 sizes decisions, not actions         |

The first use is gating merges at high throughput. People approve rules (contracts), not individual changes. A change the contracts support lands without anyone's attention. A contradicted change is held with reasons a program reads, so an agent can fix it and try again. Only an undetermined change needs a person, whose override records who let it through and why. Nothing here is specific to merges: the action, its subject and the vocabulary of reasons come from a system model ([RFC 0015](https://github.com/dekrops/wvp/pull/58)), referenced by digest.

**Separation.** The paper _Formalized Environments_ declines execution control: "a verifier that gates takes part in the execution it later judges". It allows a pre-action check derived from the same contract, as an artefact for a gating layer. This RFC keeps the verdict and the action apart. Deciders record decisions under `ledger-1`. A gate consumes them, holds no key that may record one, and acts.

**Prior art.** An existing implementation records gate actions in its ledger's core, one per decision. Alternatives says where this RFC differs, and why.

## What changes

A new specification, `gate-1`, in the encodings of `ledger-1`: one entry kind, three objects (`gate-config-1`, `gate-receipt-1`, `decision-explanation-1`), two reference kinds (`gate-config`, `explanation`) and a check. Nothing existing changes. `ledger-1` lists every `gate/acted` entry `UNINTERPRETED`, and `gate-1` reports its own result beside the ledger's (RFC 0014, section 5).

### 1. The extension and its kind

The identifier `gate` is registered in [the registry of ledger extensions](../governance/ledger-extensions.md). It has one kind, **`gate/acted`**: one action that a gate let proceed or held.

It is a **record** kind, as `ledger-1` requires of every extension kind, and the content agrees: an act changes neither who may sign what nor what is enforced. If it moved the basis, every act would void every pending decision and override, and a busy gate would block approvers. It is authorized by a service key whose `kinds` include `gate/acted`, registered by approvers at the threshold.

There is **no `gate/config` kind**. A configuration decides what holds an action, so the gate's own key must not be able to change it. That takes a threshold of approvers, and an extension kind is signed by a service key (RFC 0014, open question 10). `pin.set` already pins external material at the threshold, so the configuration is pinned.

### 2. The configuration

```json
{
  "protocol": "gate-config-1",
  "gate": "merge-main",
  "nonce": "Jq0x2b9WmN3kT5vR8yLc1A==",
  "action": {
    "model": {
      "kind": "system-model",
      "id": "example.changes",
      "digest": { "algorithm": "sha-256", "hex": "…" }
    },
    "kind": "changes.merge",
    "item": "change",
    "state": ["revision", "base"]
  },
  "contracts": [
    { "algorithm": "sha-256", "hex": "…" },
    { "algorithm": "sha-256", "hex": "…" }
  ],
  "deciders": ["decider-1"],
  "keys": ["gate-merge-1"]
}
```

| Member      | Meaning                                                                                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `gate`      | The gate's identifier, spelled as an extension identifier                                                                                                                                  |
| `nonce`     | 16 random octets, base64: the salt of subject keys (section 3)                                                                                                                             |
| `action`    | The model, by RFC 0014's reference; the model-bound `kind` whose records the action creates; its field `item`, naming what is acted on; its fields `state`, naming the exact state applied |
| `contracts` | The contracts the gate decides, by digest, ascending, 1 to 32                                                                                                                              |
| `deciders`  | The `keyId`s of the service keys whose decisions the gate reads                                                                                                                            |
| `keys`      | The `keyId`s of the gate's service keys, which sign its acts and receipts                                                                                                                  |

An action is named by the kind of record it creates, since kinds are what RFC 0015 models: a merge, a released payment or a deployment is a record that appears when the action happens. An audit compares those records with acts (Security considerations).

**Pinned.** Approvers pin the configuration with `pin.set` under the name `gate/<gate>`, to a `gate-config` reference: SHA-256 of the canonical object. A pin is a trust entry, so a new configuration voids every decision and override signed against the basis it replaces, and an act is always checked against the configuration in force at its basis. `null` retires the gate. Replay never opens the object; the `gate-1` check does, so it travels with the export.

**Which contracts hold.** A listed contract is **in force** when its `ledger-1` mode is `shadow` or `enforcing`; `off` contracts are skipped. Each contract in force is decided on its own request, and all must hold. Modes are `ledger-1`'s; a gate has none of its own.

**Fail closed.** An `enforcing` contract the gate cannot decide holds the action: no request can be formed, no configured decider answers, or the decision is stale. A missing, unpinned or unreadable configuration holds every action, whatever the modes, and so does one with no contract in force. To stop gating, approvers retire the pin and the system stops requiring the gate.

**The gate never decides.** `keys` and `deciders` are disjoint, and at every act no key in `keys` may hold `decision.recorded` among its `kinds` (`GATE_DECIDES`).

### 3. The subject

For a request a gate relies on, RFC 0014's `subject` is:

```json
{ "item": "change-7", "state": "9f2c…" }
```

- **`item`** is the value of the action kind's `item` field, at most 64 octets.
- **`state`** is the hex SHA-256 of the canonical array of the `state` fields' values, in the configuration's order. It names exactly what the action would apply: a commit and the base it lands on, a payment instruction's content, a release's artefact. Any change to that is a new state.
- **`in`**, only for a member of a combined state (below): the hex SHA-256 of the canonical text of the combined state's identifier, as the system names it.

Its canonical text is at most 222 octets, within RFC 0014's 256. The gate builds it from the system's own description of the pending action, never from what a requester says.

**Bound to the request.** The request's digest commits to its subject, and every decision names its request, so a decision about one state never supports an act about another. The ledger holds no subject. An act carries a **subject key**, SHA-256 of the canonical `{ "nonce", "subject" }` under the configuration's nonce: a holder of the configuration computes it from a record of the action, and nobody else can test a guess.

**The current request.** Each re-ask is a new request, and a gate reads the latest (RFC 0014). For a contract _c_ and subject _s_ at a position _p_, the **current request** is, among requests about _s_ whose decisions under _c_ by a configured decider are recorded before _p_, the one with the latest `cutoff`. Its decision is its last one not superseded. A gate never asks twice about one subject and contract with one cutoff; if two tie, neither is current and the contract holds. Once a later question about the same state is answered, an earlier answer stops counting, better or worse.

**Combined states.** Some systems apply a state nobody reviewed: a merge queue builds one commit from several changes on the latest base; a payment run releases a batch. The gate decides each member, one request per member and contract, with subject `{ item, state, in }`. Contracts about the member read its item and state; contracts about the combination read `in` through their inputs. Before deciding, the gate establishes from the system that the combination adds nothing but its members at those states, by means specific to the system; if it cannot, the combined action is held. It proceeds only if every member's act does.

**Overrides carried.** An override names one decision, _D_. When the gate asks again about the same item and state, the approvers have already answered, so the override also applies to a decision _D′_ when:

- _D′_ is `UNDETERMINED`, under the same contract, by a configured decider, under the act's basis, which is _D_'s;
- _D′_'s subject is _D_'s, or _D_'s with `in` added;
- _D_ and _D′_ both name an explanation (section 6), with equal `requirements`;
- every decision under the contract about _D_'s subject, recorded after _D_ and before the act, is `UNDETERMINED` with those requirements: nothing about that state changed since approvers looked.

A gap that changed is a new question. An override of a superseded decision lapses (RFC 0014), and every carry from it.

### 4. The gate's rule

For each contract in force, the gate reads the decision of the current request about the subject:

| Mode        | Current decision                                    | This contract         |
| ----------- | --------------------------------------------------- | --------------------- |
| `enforcing` | `SUPPORTED`                                         | Lets it proceed       |
| `enforcing` | `UNDETERMINED`, overridden, directly or carried     | Lets it proceed       |
| `enforcing` | `UNDETERMINED`, otherwise                           | Holds                 |
| `enforcing` | `CONTRADICTED`                                      | Holds                 |
| `enforcing` | None in time, stale, or not by a configured decider | Holds                 |
| `shadow`    | Any, or none                                        | Recorded; never holds |

The action proceeds when no contract in force holds it. `CONTRADICTED` cannot be overridden: that is a change of contract or mode. A gate may hold for reasons of its own, never proceed with less. A decision is **stale** when its basis is not the act's: a trust entry came between them, and the gate asks again.

### 5. The act

```json
{
  "gate": "merge-main",
  "subject": { "algorithm": "sha-256", "hex": "…" },
  "combination": null,
  "outcome": "held",
  "contracts": [
    {
      "contract": { "algorithm": "sha-256", "hex": "…" },
      "mode": "enforcing",
      "request": { "algorithm": "sha-256", "hex": "…" },
      "decision": { "algorithm": "sha-256", "hex": "…" },
      "override": null
    }
  ]
}
```

| Member        | Meaning                                                                                                                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gate`        | The gate; its configuration is the one pinned as `gate/<gate>` at the entry's basis                                                                                                                      |
| `subject`     | The subject key                                                                                                                                                                                          |
| `combination` | `null`, or for a member of a combined state `{ key, members }`: SHA-256 of the canonical `{ "in", "nonce" }`, and the number of members                                                                  |
| `outcome`     | `proceeded` or `held`                                                                                                                                                                                    |
| `contracts`   | One per contract in force, ascending by digest: its `mode`, the current `request` and its `decision` (entry digest), each `null` if there is none, and the `override` relied on (entry digest) or `null` |

The time is the entry's `at`, the gate's assertion. The entry is signed by a key in `keys`. A gate records **one act per action**, per member for a combined state, holds included. With two contracts an act is 1,320 octets of canonical text, 1,490 signed.

**The check.** Each append-valid `gate/acted` entry is checked against the state before it, in order, stopping at the first failure:

| Step | Check                                                                                                                                                                                                                                                    | Refusal                                                             |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| 1    | Exactly the members above, of their types, within the limits                                                                                                                                                                                             | `MALFORMED`, `LIMIT`                                                |
| 2    | A configuration is pinned as `gate/<gate>`, is given, and has the pinned digest                                                                                                                                                                          | `NO_CONFIG`, `NOT_CHECKABLE`, `CONFIG_MISMATCH`                     |
| 3    | The signer is in `keys`; no key in `keys` may sign `decision.recorded`                                                                                                                                                                                   | `NOT_GATE_KEY`, `GATE_DECIDES`                                      |
| 4    | `contracts` lists exactly the configured contracts in force, each with its mode                                                                                                                                                                          | `CONTRACTS_MISMATCH`                                                |
| 5    | Each `decision` is an earlier `decision.recorded` under that contract, for that `request`, by a key in `deciders`, under the act's basis, not superseded. Each `override` is under the act's basis and names it, or another decision under that contract | `NOT_A_DECISION`, `STALE_DECISION`, `SUPERSEDED`, `NOT_AN_OVERRIDE` |
| 6    | If `proceeded`: every enforcing contract's decision is `SUPPORTED`, or `UNDETERMINED` with an override                                                                                                                                                   | `UNSUPPORTED`                                                       |
| 7    | No earlier `proceeded` act names the same enforcing decision, or the same override with the decision it names                                                                                                                                            | `USED`                                                              |
|      | **The ledger-level result is established here.** Steps 8 to 10 need the requests and explanations.                                                                                                                                                       |                                                                     |
| 8    | Each request has its digest; its subject gives the act's subject key, and its `in` the combination's key                                                                                                                                                 | `SUBJECT_MISMATCH`                                                  |
| 9    | Each request is current for its subject and contract at the act                                                                                                                                                                                          | `NOT_CURRENT`                                                       |
| 10   | Each override naming another decision is carried as section 3 says                                                                                                                                                                                       | `NOT_CARRIED`                                                       |

A report states apart `gateValid` (steps 1 to 7, from the export and the configurations), `subjectsChecked` (steps 8 to 10, for acts whose requests and explanations were given), and the acts left `NOT_CHECKABLE`. A missing request leaves an act unchecked, never invalid. The `ledger-1` result never changes.

So a third party holding an export, the configurations and the requests checks offline that every `proceeded` action had, under every enforcing contract, a supported decision for the current request about exactly that state, or an override that applies, used once.

### 6. The receipt

The gate answers the requester with a `gate-receipt-1`, signed by a key in `keys` over `verified:gate-receipt:v1\n` and the canonical `receipt` member:

```json
{
  "receipt": {
    "protocol": "gate-receipt-1",
    "ledger": { "algorithm": "sha-256", "hex": "…" },
    "gate": "merge-main",
    "act": { "sequence": 48213, "entry": { "algorithm": "sha-256", "hex": "…" } },
    "subject": { "item": "change-7", "state": "9f2c…" },
    "outcome": "held",
    "contracts": [
      {
        "contract": { "algorithm": "sha-256", "hex": "…" },
        "mode": "enforcing",
        "request": { "subject": { … }, "cutoff": "2026-11-23T09:59:58Z", "evidence": { … }, "nonce": "…" },
        "decision": { "algorithm": "sha-256", "hex": "…" },
        "value": "UNDETERMINED",
        "override": null,
        "missing": null,
        "explanation": {
          "protocol": "decision-explanation-1",
          "requirements": [
            { "id": "CHECKS_PASSED", "value": "TRUE" },
            {
              "id": "REVIEWED_BY_ANOTHER",
              "value": "UNKNOWN",
              "causes": [{ "cause": "absent", "kind": "changes.review", "sources": ["changes.api"] }]
            }
          ]
        }
      }
    ],
    "issuedAt": "2026-11-23T10:00:01Z"
  },
  "signature": { "scheme": "Ed25519", "keyId": "gate-merge-1", "encoded": "…" }
}
```

Per contract it carries the request in full, the decision, its value, the override and the explanation. `missing` says why there is no decision: `no-decision` (none in time), `stale`, `not-decidable` (no request could be formed) or `ledger` (unreachable).

**The explanation**, `decision-explanation-1`, is what the decider computed with the decision: per requirement, its Language 1 value and, unless `TRUE`, why. The decider names its digest as `decision.recorded`'s optional `explanation`, under the reference kind `explanation`. It is a function of the contract and the package, so recomputation checks it as it checks the decision. A `FALSE` requirement has `by`: the statement digests of the records that make it `FALSE`, ascending, at most 16. An `UNKNOWN` one has `causes`, collected where evaluation reached `UNKNOWN`, from a closed set:

| Cause           | When ([Language 1](../protocols/work-contract/v1/SPEC.md), section 7)    | Names                      | What would decide it                      |
| --------------- | ------------------------------------------------------------------------ | -------------------------- | ----------------------------------------- |
| `absent`        | An `exists` found no record making it `TRUE`, and its kind is not closed | `kind`, accepted `sources` | A record that satisfies it, or a listing  |
| `not-closed`    | A `forall` found no counterexample, and its kind is not closed           | `kind`, accepted `sources` | A completeness statement as of the cutoff |
| `missing-field` | A comparison read an absent optional field                               | `kind`, `field`, `record`  | The field                                 |
| `conflict`      | The kind is open because accepted records with one key disagree          | `kind`, `records`          | A corrected record                        |

Kinds and sources are the contract's names: for a contract bound to a system model, the model's qualified names (`changes.review`, `changes.api`), never the gate's. An agent acts on them: `by` names the records to change, `absent` the kind of record to obtain, and `missing` says to try again later.

**Checked against the ledger.** Everything in a receipt but `missing` and `issuedAt` is in the act it names, or is the preimage of a digest the act or its decisions name. A requester verifies the signature under a key the ledger registers for `gate/acted`, finds the act by sequence and entry digest, and checks that it names these requests and decisions, that the decisions have these values and explanations, and that the outcome follows section 4. With the configuration, it runs the whole check. A signed `proceeded` receipt with no such act proves the gate answered one way and recorded another. A held receipt may have `act` `null` when the ledger is unreachable: the gate's word alone, enough to hold, never to proceed.

### 7. Throughput

- **One small entry per action.** No entry batches actions: each act is checked alone, and a batch would hide which action relied on what. The writer batches appends and checkpoints (RFC 0014, section 10).
- **Synchronous, before proceeding:** the configuration and modes in force, cached and refreshed on trust entries, which are rare; each current decision, appended; the gate's own `proceeded` act, given a sequence by the writer, so that no action proceeds on an act that might not land; and, under a witness policy, the trust chain up to the act's basis witnessed. Decisions and acts after the last checkpoint are covered by the next.
- **Deferred:** checkpoints and inclusion proofs; held acts, since holding changes nothing; receipts; steps 8 to 10; recomputation.
- **Parallel.** The gate asks under every contract at once and waits for the slowest.

### 8. Failure modes

| Failure                                       | Some contract in force `enforcing`                            | Every contract in force in `shadow`          |
| --------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------- |
| The gate is down                              | Held: the system applies the action only on the gate's answer | Proceeds with no act; an audit sees the gap  |
| Configuration missing, unpinned or unreadable | Held                                                          | Held: no configuration never means shadow    |
| Ledger unreachable for reading                | Held; receipt with `act` `null`, `missing` `ledger`           | Proceeds, on the last state the gate read    |
| Writer refuses or cannot append               | Held: a `proceeded` act is appended first                     | Proceeds; the act is appended later, or lost |
| Decision late                                 | Held, `no-decision`; asked again on the next event            | Proceeds, with `decision` `null`             |
| A trust entry between decision and act        | Held; asked again under the new basis                         | Proceeds; recorded under the new basis       |
| An enforcing contract cannot be decided       | Held, `not-decidable`                                         | Does not arise                               |
| Trust chain unwitnessed under a policy        | Held                                                          | Proceeds                                     |

Everything fails closed in `enforcing`. Shadow fails open by design. A contract put in `enforcing` while the gate cannot read the ledger takes effect when it can.

## Outcomes that change

None. `gate-1` is a new identifier with its own vectors (RFC 0001, invariant 2), and every `ledger-1` result is unchanged.

New refusal codes, all of the `gate-1` check: `NO_CONFIG`, `NOT_CHECKABLE`, `CONFIG_MISMATCH`, `NOT_GATE_KEY`, `GATE_DECIDES`, `CONTRACTS_MISMATCH`, `NOT_A_DECISION`, `STALE_DECISION`, `SUPERSEDED`, `NOT_AN_OVERRIDE`, `UNSUPPORTED`, `USED`, `SUBJECT_MISMATCH`, `NOT_CURRENT`, `NOT_CARRIED`. `MALFORMED` and `LIMIT` are RFC 0014's.

## Compatibility

- **`ledger-1` verifiers** need no change: they list acts `UNINTERPRETED`.
- **Ledgers** gain a gate by two trust entries: `key.add` of its key with `kinds` `["gate/acted"]`, and `pin.set` of its configuration.
- **Deciders** need not change. Without `explanation`, receipts carry values without causes, and no override is carried.
- **Verifiers** are new, with a profile under RFC 0004, rule 3: _Gate verification_.

## Vectors

In `test-vectors/gate/v1`, over synthetic models of a change system and a payment system, at least:

- **Valid:** `proceeded` on `SUPPORTED` under one, two and 32 contracts, and on an override; each hold of section 4; a `CONTRADICTED` shadow contract beside a supported enforcing one; an override carried to a re-ask and to a combined state; a combination of three, one held; a receipt per outcome, and one with `act` `null`.
- **Refused,** every code, and: `proceeded` on `UNDETERMINED` without an override, on `CONTRADICTED`, and with no decision; a decision about another subject, or of an earlier request; one decision, and one override, used twice; an override carried to another item, state or contract, with other requirements, or past a changed decision; an `off` contract listed; an act under a retired configuration.
- **Receipts:** an explanation or value other than the decision's; a receipt signed in the entry domain; `proceeded` with no act.
- **Order:** steps 5 and 6 failing at once, and 8 and 9.

All synthetic, with public test keys.

## Security considerations

This RFC touches signing inputs, key validity, time and what a result may be relied on for (RFC 0001, section 9.1). **The adversary** may be the gate's operator, holding its keys and perhaps the writer's; the requester, who controls the change; or a decider's operator. **Assumed:** RFC 0014's assumptions; a threshold of approvers is honest; the system applies the action only on the gate's answer.

**Shown by the ledger, through the check:**

- _Acting without a decision:_ `UNSUPPORTED`.
- _Replaying a decision onto another subject._ A decision names its request, the request commits to its subject, and the act's subject key must match every request it relies on (`SUBJECT_MISMATCH`).
- _A stale decision after the subject changed._ A new state is a new subject, which no old decision names. A later answer about the same state makes an earlier one not current (`NOT_CURRENT`). A decision under an earlier trust state is `STALE_DECISION`.
- _An override used twice._ It supports one `proceeded` act directly (`USED`), and is carried only to the same item and state while nothing about it changed.
- _A gate reconfiguring itself, dropping a contract or deciding._ The configuration is pinned at the threshold; an act lists every contract in force (`CONTRACTS_MISMATCH`); a gate key may not sign decisions (`GATE_DECIDES`).

**Not shown by the ledger:**

- _An action with no act, against its act, or about another state._ The ledger shows what the gate signed. An audit lists the system's records of the action kind and finds each one's `proceeded` act by subject key; a record with none is a bypass.
- _A combination's content._ That it adds only its members is the gate's reading of the system.
- _When the gate asks._ One that does not ask again after new evidence acts on the latest answer it has.
- _Withholding._ A writer colluding with the gate can delay a later, worse decision so that an earlier one is acted on. Witnessing bounds the window and does not close it (RFC 0014).
- _One operator behind two keys._ The ledger shows a gate key and a decider key, not who runs them. One party running both is the verifier that gates, which the paper warns against.
- _A wrong decision or override,_ RFC 0014's boundary.

**Privacy.** Subjects stay out of the ledger: only holders of the configuration can test a guess against a subject key. A receipt carries the subject and requests in clear and is for the requester. Holds, outcomes, modes and timing are in clear to anyone given the export.

**Primitives.** Ed25519 and SHA-256, as RFC 0014. None is new.

**Review.** No person other than the author has reviewed this RFC. Under RFC 0001, section 9.1, it cannot become Final until a competent reviewer has, and is named here.

## Formal semantics

Nothing is proved with this RFC. Worth proving in Lean, over RFC 0014's model with the check added, signatures assumed and digests injective:

1. Every `proceeded` act passing steps 1 to 7 names, for every enforcing contract of the configuration at its basis, a `SUPPORTED` decision by a configured decider under that basis, not superseded, or an `UNDETERMINED` one with an override of a decision under the same contract.
2. With steps 8 to 10, each such decision answers the current request about the act's subject, and each override is carried only to the same item and state, with equal requirements.
3. No decision, and no override directly, supports two `proceeded` acts.
4. Changing a shadow contract's decision changes no act's validity.
5. An act with an enforcing contract and no decision is valid only if `held`.
6. Removing every `gate/acted` entry changes no `ledger-1` state, basis or result.

**Tested only:** explanations, receipts, limits. **Neither:** that the gate did what it recorded, and that the subject described what the system applied.

## Alternatives

- **`gate.acted` in the core.** The writer could refuse an unsupported act at append, which is stronger than reporting it. But every ledger verifier would carry the vocabulary of gates, ledgers without one would carry rules they never use, and gating changes faster than ledgers. Here an invalid act can be appended, and a relying party that needs gate validity runs the check.
- **No record of action.** Overrides' use, holds and receipts would have nothing to point at.
- **The verifier gating directly.** A verdict could be dropped after it was seen, and the verifier would take part in the execution it judges. Kept apart, the decider records first and the gate consumes.
- **A `gate/config` kind.** Signed by a service key, a gate could reconfigure itself.
- **One act per decision.** One action under several contracts would be spread over several entries, and a held decision would leave nothing to anchor a receipt.
- **The subject in clear.** It discloses guessable identifiers, which RFC 0014 keeps out of the ledger.
- **Requests that name the one they follow** (RFC 0014, open question 11). A change to the core request; ordering by `cutoff` answers it for a gate's own requests.

## Open questions

1. **The explanation's home:** here, beside `ledger-1`, or its own specification; and the exact rule choosing `by`.
2. **Pin names.** Whether `ledger-1` reserves names starting with a registered identifier (`gate/…`) to that extension.
3. **Modes per gate.** Modes are per contract: one enforced at one gate and tried in shadow at another needs two versions.
4. **Actions in system models.** Whether a model's `behavior/` parts should name actions, their items and states.
5. **Combined states.** Whether a model can say how a combination is formed, so a checker confirms its members from records.
6. **Refusing at append.** Whether a writer may refuse an act failing steps 1 to 7, as a policy beyond `ledger-1`.
7. **Audit as a contract.** Whether acts should be readable as evidence, so that "every applied action has a `proceeded` act" is a contract over the system's listing.
8. **Several gates on one action.** Both must let it proceed; nothing ties them.
9. **Limits.** Proposed: 32 contracts per gate, 64 octets of item, 100 members per combination, 16 records in `by`, 64 KiB per receipt.

## Decision

Not made. The review period of RFC 0001, section 5, has not started. This RFC will be accepted on the maintainers' judgement alone only if it says that it had no outside review (section 7.4).

## Implementation

Not implemented.

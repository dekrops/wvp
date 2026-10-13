# An experiment: the claim registry in Veil

Informative, and an experiment. [Veil](https://github.com/verse-lab/veil) is a framework in Lean for specifying transition systems, model checking small instances of them and proving their invariants with an SMT solver. This directory asks one question of it: what does it add, for the claim registry, to the model that is already proved in [`formal/lean/Verified/Registry.lean`](../../../formal/lean/Verified/Registry.lean)?

Nothing else in this repository depends on Veil. It has its own Lean toolchain (4.32.0; the definitions here pin 4.24.0), an SMT solver, and a widget built with npm.

```sh
bash conformance/experiments/veil-registry/run.sh [a directory to keep the Veil checkout in]
```

needs elan, Node.js and Clang. The first run builds Veil, which takes many minutes.

## The property

> In every reachable state, at most one claim holds a given unit.

**What "holds" means.** In [claim registration v1](../../../protocols/claim-registration/v1/SPEC.md), a claim holds its unit while it is open, answered with evidence, under an open dispute, or refused with the claimant's dispute of the refusal upheld. A refused, expired, withdrawn or superseded claim does not. The models here have one relation, `holds`, and one action, `release`, for every way of ceasing to hold. They do not distinguish the states.

**What a unit is.** The pair of an agreement's unit key and the claim's nullifier. Here, an uninterpreted type.

## Three models

| Model                                           | What it is                                                                                                                              | Is it the protocol?                                                                                                    |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| [`RegistryAtomic`](RegistryAtomic.lean)         | One registry. A registration is accepted when its identifier is new and no claim holds the unit, and is appended in one step            | **Yes**, abstracted. Claim registration v1 defines one log                                                             |
| [`RegistryReplicated`](RegistryReplicated.lean) | Several replicas. Each accepts a registration when no claim **it has observed** holds the unit, and learns of the others' entries later | **No.** A deployment the protocol does not describe. It is also the model of one registry showing two parties two logs |
| [`RegistryOrdered`](RegistryOrdered.lean)       | The same replicas, where one accepts a registration only once it has observed every registration there is                               | No. The same deployment with the condition that makes it safe                                                          |

Each has many claimants (any claim may be registered at any time), competing claims for one unit, receipts, and release. The replicated models add delayed observation.

## Results

| Model                | Explicit-state model check                               | Inductive invariant                                                                                                            |
| -------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `RegistryAtomic`     | No violation, 3 claims and 2 units, 99 states            | **Proved** for any number of claims and units: 3 clauses, preserved by both actions; the solver's proofs reconstructed in Lean |
| `RegistryReplicated` | **Violated in two steps**                                | Not attempted: the property is false                                                                                           |
| `RegistryOrdered`    | No violation, 3 claims, 2 units, 2 replicas, 2433 states | **Proved** for any number of claims, units and replicas: 5 clauses, preserved by all three actions; proofs reconstructed       |

The counterexample, as Veil prints it, is the smallest there is:

```text
State 1 (via register(c=0, r=1, u=0)):   replica 1 accepts claim 0 for unit 0
State 2 (via register(c=1, r=0, u=0)):   replica 0, which has not observed claim 0, accepts claim 1 for unit 0
    holds = [0, 1]                       two claims hold one unit, and each has a receipt
```

**What this says, exactly.** Unit exclusivity is a property of a log that is appended to in one order. It is not a property of a registry's code, and it does not survive a deployment in which two parts of a registry accept entries without having seen each other's. The condition that restores it (`RegistryOrdered`) is that an entry is accepted only by something that has observed every earlier entry: a total order. Signed heads let two parties detect afterwards that this failed; nothing in the protocol prevents it.

**What it does not say.** That any deployed registry is safe. `RegistryAtomic` and `RegistryOrdered` are abstract models with three or five relations; whether a service appends atomically is a fact about the service.

One clause of `RegistryOrdered`'s invariant was found the way Veil intends: the first attempt at "a claim has one receipt" was not inductive, the tool showed a state with a receipt for a claim never registered, and the clause that excludes it was added.

## Against `Registry.lean`

|                               | `Registry.lean` (in `formal/lean`)                                                                                                          | These models                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| What is modelled              | The audit's rule for each entry of one log: six claim states, disputes and their resolution, withdrawal, supersession, the open-claim limit | Registration and release                                                    |
| Unit exclusivity              | `accepted_log_units_exclusive`: in every log an audit accepts from its start                                                                | The same statement, for the abstraction                                     |
| Other properties              | Five more: final claims persist, disputes keep states, a disputed claim cannot be closed, the limit, the replacement comes next             | None                                                                        |
| Concurrency                   | None. A log is a list                                                                                                                       | Interleaved actions by any claimant, at any replica                         |
| How it is proved              | By induction, in Lean, by hand; the kernel checks it; standard axioms only                                                                  | An SMT solver finds the proof; with reconstruction on, the kernel checks it |
| How a false property shows up | A proof that does not go through                                                                                                            | A trace, minimal, in seconds                                                |
| Toolchain                     | Lean 4.24.0, no dependency                                                                                                                  | Lean 4.32.0, an SMT solver, five Lean libraries, Node.js, Clang             |

The sequential theorem is the stronger statement about the protocol as specified, because it is about the actual rules. Veil's contribution here is the second row of the results: it turned "this assumes an atomic log" from a sentence in a README into a two-step trace and a proved condition.

## Recommendation

**Do not adopt Veil as a dependency now.** Keep this experiment, isolated, and rerun it by hand.

- The protocol has one log. For one log, the existing Lean model says more, with a smaller trusted base.
- Veil 2.0 is a pre-release, on a Lean version eight releases ahead of the one pinned here, with a heavy toolchain. Tying the normative definitions to it would trade their independence for automation they do not need.
- **It should be taken up again when the protocol specifies something concurrent.** Two open questions would: anchoring stream heads at a registry (B1), and a Merkle log with witness-cosigned heads (B2). A protocol with witnesses, quorums and delayed messages is what Veil is for, and finding the inductive invariant by counterexample is far cheaper than by hand. The RFC for either should come with a Veil model, as RFC 0003 came with a Lean one.

## Assumptions of these models

- Claim identifiers are never reused, anywhere (`registered` is global, even where observation is not).
- A receipt is issued in the same step as the entry is accepted.
- Signatures, documents, times, deadlines, agreements and the open-claim limit are not modelled.
- `release` may happen at any time to any holding claim: the models allow more behaviour than the protocol, which is the safe direction for a safety property.
- Replicas do not fail and do not lie; they only lag.

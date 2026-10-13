# RFC 0005: Derived assertions

|            |                                                                                           |
| ---------- | ----------------------------------------------------------------------------------------- |
| RFC        | 0005                                                                                      |
| Status     | Draft                                                                                     |
| Author     | Zin Nam                                                                                   |
| Created    | 2026-10-13                                                                                |
| Affects    | A new protocol version or profile would carry it. Work Contract Language 1 is not changed |
| Supersedes | Nothing                                                                                   |

A verifier may compute a record from admitted evidence by a named, deterministic method, and let a contract read it. Today every record a contract reads is a source's signed word. The first method is the recomputation of a [Cedar](https://www.cedarpolicy.com/) authorization decision. For a relying party it means a contract can require that an action was permitted by the policies in force, without trusting the system that enforced them.

## Motivation

A work contract often requires that someone was authorized. Today there are two ways to establish it, and both rest on a source's word for the conclusion:

- a directory lists authorities and the contract compares a limit with an amount ([example](../protocols/work-contract/v1/examples/purchase-order-approval)). This works for a flat rule and not for roles, hierarchies, delegation or exceptions;
- the enforcing system signs a decision record ([example](../protocols/work-contract/v1/examples/purchase-order-authorization/README.md)). The contract then trusts the enforcer for the decision.

A relying party in a dispute trusts neither. It holds, or can obtain, the policy set and the directory's records as signed evidence. The decision follows from those by a published rule. Nothing in the protocol lets a verifier apply the rule and say so in a way a second verifier can check.

The second example already contains a contract that accepts only a recomputation, and shows it `UNDETERMINED` in every case, because no such record can exist today.

The same shape recurs beyond authorization: any conclusion that follows deterministically from admitted evidence by a method too rich for the contract language and specified elsewhere.

## What changes

### 1. A derived record

A **derived record** is a record that a verifier adds to an environment before evaluation, computed by a **method** from admitted statements. It has a kind and fields like any record. Its source is a name reserved for the method.

1. A reserved source name is never read from a signed statement, whoever signed it and whatever the trust registry says. Attested and derived records are therefore distinguishable by source, and a contract chooses between them by the sources it lists.
2. A contract accepts a derived record as it accepts any other: by listing the method's source name for a kind. A contract that does not list it never reads one. No existing contract changes meaning.
3. A method yields a record or nothing. It never yields a record that says "unknown": a contract could compare against it and turn not knowing into `FALSE`. Absence, with the kind left open, is how the language already represents not knowing.
4. A derived kind is closed only when the method's definition says so. For a method that derives one record per event, that is: every source the contract accepts for the events declared them complete, the method read events from exactly those sources, and every event yielded a record. Otherwise "there is none" would be concluded from a question nobody answered.

### 2. A method

A method is identified by a name and a version, and is defined by a specification with vectors. It states:

- the statements it reads: their kinds, and the sources it may accept them from;
- its preconditions, each with a code. If one fails the method yields no record and reports the codes, as a set;
- the function from its inputs to the record's fields, by reference to a specification a second party can implement;
- every external language version the function depends on. A different one is a different method version;
- the subset of the external language it evaluates. Anything outside it is a failed precondition, never evaluated on the assumption that it does not matter.

**The profile.** How a method reads evidence for a given contract (which kinds and fields identify the event and the request, which sources are accepted for what) is a value with a canonical form. Its digest is part of every derivation. Two derivations under different profiles answered different questions.

### 3. The derivation

For every derivation a verifier reports two things, kept apart.

The **core**, which every implementation of the method must reproduce byte for byte: the method, its version and language version; the profile's digest; the event's identifier and the request; the digests of the inputs and the interval over which they were valid; every statement relied on, by digest and role; the outcome; the failed preconditions. Its digest is the derivation's **commitment**.

The **diagnostics**, which are one implementation's own: the engine binding it used, the engine's raw answer whenever it gave one, and its messages. They are committed to separately. The raw answer is kept apart from the outcome and never becomes it: an engine that answers Allow after skipping a policy that failed to evaluate is reported as having answered Allow, and the outcome is that nothing was derived.

The decision's commitments gain the commitments of the derivations, so that a record of the decision names what was derived and from what.

**Bindings.** The evaluation also commits to which requirements depend on which derivations. A derivation is not about a requirement, and one derivation may serve several, so the binding belongs to the evaluation and not to the derivation. It is read from the contract: a requirement depends on a method's derivations if its predicate quantifies over the derived kind and the contract accepts the method's reserved source for that kind. Such a requirement is bound to every derivation of that kind, including one that yielded no record, because that absence is what its quantifier saw. A binding names the requirement, the method and version, and each derivation by its event and commitment.

This says exactly which requirements a derivation can affect. It does not say which record satisfied or refuted a requirement: the evaluator of Work Contract Language 1 reports a value per requirement and no witnesses. Whether it should is an open question below.

A report states, for every requirement, whether the records it read were attested or derived. The two are never merged into one word.

### 4. Replay

A second verifier that is presented with a derivation believes none of it. It authenticates every statement against its own trust registry; compares the contract and the profile with what the presented result commits to; computes every derivation again from the statements; evaluates the contract again; and only then compares commitments. A digest says which content is meant. It is never a reason to accept the content.

A missing input, an unsupported method or an unsupported method version is a failure to verify. It is never a pass.

### 5. The first method: `cedar-authorization`

Inputs, each an admitted statement in the existing body forms: one work event; one policy set with its schema; entities; and completeness statements for policy sets and entities. Policy sets and entities carry the interval over which they were valid.

A record is read only if it was valid at the time of the event. The current policy set is never a substitute for the one in force then.

Preconditions, each a refusal to derive:

| Code                      | Holds when                                                                                                                                                                                   |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `REQUEST_NOT_ESTABLISHED` | Exactly one account of the event, naming a principal, a resource and a time                                                                                                                  |
| `POLICY_SET_NOT_IN_FORCE` | A policy set was valid at the event's time, and its source declared its policy sets complete as of that time or later                                                                        |
| `CONFLICTING_EVIDENCE`    | One policy set for that time; no event and no entity has two accounts that differ                                                                                                            |
| `POLICIES_NOT_VALID`      | The policies validate against the schema, strictly                                                                                                                                           |
| `ENTITY_NOT_PRESENT`      | The principal, the resource, every ancestor, every entity an attribute refers to and every entity a policy names is present, and every accepted entity source declared its entities complete |
| `ENTITIES_NOT_VALID`      | The entities validate, and no declared attribute is absent unless its source states that it has none                                                                                         |
| `ENGINE_NOT_AS_NAMED`     | The engine's Cedar language version is the one the profile names                                                                                                                             |
| `CONTEXT_NOT_SUPPORTED`   | The schema declares no request context for the action                                                                                                                                        |
| `FEATURE_NOT_SUPPORTED`   | No policy templates or links, and no entity tags                                                                                                                                             |
| `LIMIT_EXCEEDED`          | The policies, the schema, the entities and the statements are within stated sizes                                                                                                            |
| `EVALUATION_ERROR`        | Cedar reports no evaluation error. An errored policy was skipped, and it may have been the one that decides                                                                                  |

Function: Cedar's authorization, as its specification defines it, at the named language version. Allow gives a record with `permitted` true, Deny one with `permitted` false.

Each precondition exists because of one way the engine turns missing input into a definite answer: an absent permit is a denial by default; `in` and `has` on an absent entity or attribute are quietly false; a policy that fails to evaluate is skipped.

## Outcomes that change

None for any existing input. A package without a derivation, and a contract that lists no reserved source, are evaluated exactly as today.

A contract that lists a method's source is one no verifier can satisfy today, since no statement may carry that source. With this RFC such a contract can become `SUPPORTED` or `CONTRADICTED`. That is a new outcome for an input that exists, so by [RFC 0001](0001-standards-process.md), section 6, this is a new version. Whether that is a version of the package protocol or a profile under [RFC 0004](0004-conformance-profiles.md) is an open question below.

## Compatibility

- **Producers** change nothing unless they want a derivation: then they include the method's input statements.
- **Verifiers** that do not implement a method refuse a package that requires it as unsupported, as they refuse an unknown version. They MUST NOT evaluate it without the derivation and report the result as if nothing were missing.
- **Relying parties** read one more thing in a report: attested or derived, per requirement.
- **Work Records** made before this are unaffected. One made with it names the derivations by commitment.
- **[RFC 0003](0003-wvp-0.3.md).** That version makes a completeness statement say what it covers and closes a kind only when every accepted source declared it. Section 1, rule 4, is stated in the same terms.

## Vectors

For the derived-record rules: a signed statement with a reserved source (not read); a contract that lists a reserved source and a package without the method's inputs (requirement `UNKNOWN`); a derived kind left open by an incomplete event listing; by a source the method did not read; a derived kind closed.

For `cedar-authorization`: one case per precondition where Cedar alone gives a definite answer and the method yields no record; a clean Allow; a clean Deny; a policy set that came into force after the event; a stated absence and an unstated one.

For replay: a statement altered after signing; a body altered; a statement removed; the profile altered; the contract altered; a presented outcome altered with digests to match; the same statements in another order.

Also: a contract with two requirements over one derived kind, bound to the same derivation; and an engine that answers Allow beside an evaluation error.

A corpus of 22 such cases exists with the experimental implementation named below and would be proposed with this RFC's review.

## Security considerations

This touches what a verifier accepts as a fact, so it is required.

- **An adversary controls** the package: which statements are included and which are left out, and everything it presents as a result.
- **Prevented:** passing off a signed claim of a derivation as one (reserved source); obtaining a denial or a permission by omitting a policy, an entity or an attribute (preconditions, with completeness declared by the source and not by the package); obtaining a permission from an evaluation that skipped an errored policy; presenting today's policy set for yesterday's action; presenting a result with consistent digests that the evidence does not yield (replay recomputes; it never compares a presented value with another presented value).
- **Not prevented:** a source that signs a false policy set, a false entity, a false validity interval or a false completeness statement. A verifier that derives from false evidence derives a false record, correctly. The trust registry is the control, as for every other record.
- **Not prevented:** a wrong mapping in the profile from the event's names to the engine's entity identifiers. The profile's digest commits to the mapping. Nothing establishes it.
- **New attack surface:** the verifier runs an external engine over input from the package. Sizes are bounded by a precondition. Evaluation time is not, and an implementation needs its own limit; what a verifier reports when it gives up is an open question.
- **A wider trusted base:** a verifier that implements a method trusts that engine's implementation of its specification.

## Formal semantics

- **Proved** (Lean, with the engine as a parameter, so for any engine): a definite outcome implies no failed precondition and an error-free answer; a failed precondition gives no record whatever the engine would answer; without a usable policy statement, from an unaccepted source, or without declared completeness, there is no definite outcome; every dependency of a derivation is a presented, usable statement; a reproduced replay means the presented result equals the recomputation; a result under a profile with another digest is refused.
- **Assumed:** that different profiles have different digests (collision resistance); that the engine implements its specification.
- **Tested:** two implementations of the method, in Scala and in Rust, reproduce each other's commitments on the 22 cases.
- **Neither:** the correspondence between the formal model and either implementation; the entity preconditions and the rule for closing a derived kind in the formal model.

The proofs are not yet published in this repository. They would be, with the method's specification, before Review.

## Alternatives

- **Only attested decisions.** Simpler, and already possible. It leaves the relying party trusting the enforcer for the conclusion.
- **A typed external predicate in the contract language**, `authorized(principal, action, resource)`. It changes Work Contract Language 1, its typing rules and its formal semantics, for one method. A derived record needs no change to the language. The predicate can be revisited when a second method shows what is common.
- **Sign the derived record with a verifier key.** Then it is an attestation by the verifier, and a second verifier checks a signature, not a computation. The point of derivation is that nobody need be believed.
- **Commit to diagnostics with the result.** Then two implementations with different messages, or different bindings to one engine, never agree. Hence the separate commitment.
- **Reimplement the policy language in the contract language or in the formal model.** A second implementation of an engine that already has a specification, a formal model and a production implementation.

## Open questions

1. A new version of the package protocol, or a profile of `wvp-0.3` under RFC 0004?
2. Is a method's specification one of the protocol's specifications, or a registered document beside them? The first method depends on an external specification that changes on its own schedule.
3. Is there a registry of methods and reserved source names, and who admits a method to it?
4. Which Cedar features belong to the method: request context (which needs the context as evidence of the request), templates and links, entity tags.
5. **Independence.** The two implementations that exist call the same Cedar engine, one through its Java binding and one directly, and have one author. They are two implementations of the method and one of Cedar. Does that satisfy RFC 0001's requirement of two independent implementations for Final, and if not, what does?
6. What does a verifier report when it stops an evaluation that takes too long: a failed precondition, which every verifier must then agree on, or its own resource limit, which they need not?
7. Should the evaluator report, for each requirement, the records that decided it? Bindings could then name a witness. It would change the specified output of Work Contract Language 1.
8. How does a binding state the language version of the engine it carries? One binding examined reports a fixed string whatever engine it contains. The method must name the engine's version, and an implementation must be able to establish it.

## Decision

Written by the maintainers when the review ends.

## Implementation

Filled in later. For orientation only, and no part of the proposal: an experimental implementation exists at the steward, in two runtimes, behind formats whose names say `experimental`. It makes no claim of conformance, since there is nothing yet to conform to.

# RFC 0001: The WVP standards process

|            |                                                                 |
| ---------- | --------------------------------------------------------------- |
| RFC        | 0001                                                            |
| Status     | Accepted                                                        |
| Author     | Zin Nam                                                         |
| Created    | 2026-10-11                                                      |
| Affects    | Every specification in this repository, and this process itself |
| Supersedes | Nothing                                                         |

This RFC defines how the Work Verification Protocol (WVP) family of specifications changes: who may propose a change, how it is reviewed in public, who decides, what a change must come with, and what may never change. It introduces no change to any specification, vector or expected outcome.

It took effect when it was merged. Section 12 says how it was adopted and how it is changed.

## 1. Conventions

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, MAY and OPTIONAL in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in capitals.

- A **specification** is a document in this repository with a header that gives it an identifier and a version.
- A **vector** is a file of the conformance corpus under `test-vectors/`. Its **expectation** is the outcome it states for its input.
- An **outcome** is everything a specification defines as the result of processing an input: canonical bytes, a digest, a decision, a report member, a refusal code, a standing.
- An **implementation** is any software that processes inputs as a specification defines.

## 2. What this process governs

It governs the specifications and the conformance corpus in this repository, and this process.

It does not govern any implementation, including the steward's. It does not govern products built on the protocol: persistence, application interfaces, deployments, user interfaces and operations are outside it. [The architecture map](../governance/architecture.md) draws that line.

Nothing in this process, and nothing in this repository, claims that WVP is a standard of a standards body. It is a protocol published by its steward, changed in public.

## 3. Roles

- **Steward.** Krops GmbH. It publishes this repository, appoints maintainers, and decides when the maintainers cannot.
- **Maintainers.** The people listed in [`governance/MAINTAINERS.md`](../governance/MAINTAINERS.md). They review, decide and merge.
- **Authors.** Anyone. An author needs no affiliation and no permission to propose a change.
- **Implementers.** Anyone who implements a specification. An implementer's report of an ambiguity is the most valuable input this process has.

The steward is also an implementer and sells products built on the protocol. That is a conflict of interest, and this process does not pretend otherwise. Its answer is that every decision is made in public, with written reasons, under the invariants of section 6, which bind the steward as they bind everyone.

## 4. Three kinds of change

| Kind              | What it is                                                                                                                                       | What it needs                                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| **Editorial**     | Changes no outcome and resolves no ambiguity: spelling, structure, a broken link, a clearer sentence that both readings already agreed on        | A pull request, reviewed by a maintainer                                                                             |
| **Clarification** | Decides a case that the text left open, where **no published vector decides it** and the decision contradicts no published vector                | An issue stating the case and the readings, at least 7 days of public review, text, and vectors for the decided case |
| **Normative**     | Anything else: a new specification, a new version, a new object, code or check, a change of any outcome, a deprecation, a change to this process | An RFC                                                                                                               |

When it is unclear which kind a change is, it is the more demanding one. A maintainer MUST NOT merge a change as editorial if any implementer has reported that the two versions of the text read differently to them.

A clarification that turns out to change the outcome of a published vector was not a clarification. It MUST be withdrawn and proposed as an RFC.

## 5. The RFC lifecycle

An RFC is a file `rfcs/NNNN-short-title.md`, numbered in order of its pull request, written from [the template](0000-template.md).

```text
Draft ──▶ Review ──▶ Accepted ──▶ Implemented ──▶ Final
  │          │           │
  │          ├──▶ Rejected
  └──────────┴──▶ Withdrawn            any accepted RFC ──▶ Superseded
```

| Status          | Meaning                                                                                                | Entered by                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| **Draft**       | A proposal under construction, in an open pull request. Anyone may comment                             | Its author opens the pull request                                              |
| **Review**      | The author considers it complete. The public review period runs                                        | A maintainer, on the author's request, once the RFC has every required section |
| **Accepted**    | The change will be made. Nothing normative has changed yet                                             | The maintainers' decision (section 7), after the review period                 |
| **Implemented** | The specification text and the vectors are published, and the reference implementation reproduces them | A maintainer, when section 8.1 holds                                           |
| **Final**       | The change has met the interoperability bar                                                            | A maintainer, when section 8.2 holds                                           |
| **Rejected**    | The change will not be made. The RFC is merged with the reasons, so the question has a record          | The maintainers' decision                                                      |
| **Withdrawn**   | Its author no longer proposes it                                                                       | The author                                                                     |
| **Superseded**  | A later RFC replaces it. It names that RFC                                                             | The later RFC's acceptance                                                     |

Rules:

1. The review period MUST be at least **14 days**, in public, in the RFC's pull request. A security fix MAY use a shorter period under section 9.3.
2. An RFC in Review MUST NOT change in substance without the review period restarting. A maintainer says in the pull request whether a change is one of substance.
3. A decision to accept or reject MUST be written in the RFC itself, with its reasons and the objections that were not adopted, each answered.
4. Accepted, Rejected and Withdrawn RFCs are merged. An RFC is never deleted, and after Accepted its content changes only to record its status and what implements it.
5. Any person MAY ask for a rejected or accepted RFC to be reconsidered by opening an issue with new information. Disagreement alone is not new information.

## 6. Compatibility invariants

These hold for every change, whoever proposes it. An RFC that would break one of them MUST be rejected, unless it is an RFC that changes this section, which needs the steward's written decision as well as the maintainers'.

1. **A published expectation is never changed.** No vector that has been published on this repository's `main` is edited so that its expectation differs, and none is removed.
2. **A change of outcome is a new version.** If any input would have a different outcome, the result is a specification with a new identifier, in a new directory, with its own vectors. The earlier version and its vectors remain, unchanged.
3. **Versions are never interchanged.** An implementation of one version MUST refuse an object of another, and no specification may define a silent conversion between versions.
4. **A revision only adds.** Within one version, an RFC MAY add an object, a check that applies only to the new object, or vectors, if every published vector keeps its expectation and no input that had a defined outcome gets another. Such a revision is recorded in the specification's header.
5. **Deprecation removes nothing.** A deprecated version stays published with its vectors, and stays verifiable. Deprecation says that new producers SHOULD NOT emit it and why.
6. **Implementation behaviour is never normative.** Where a specification is silent, the behaviour of an implementation, the reference implementation included, decides nothing. The case is an ambiguity, to be resolved under section 4.
7. **The relying party's trust is never taken from input.** No change may make a verifier accept a key, an authority, an expectation or a verdict because the object under verification says so.

## 7. Who decides

1. The maintainers decide by consensus: no maintainer objects after the review period.
2. Where the maintainers cannot agree within 30 days of the end of the review period, the steward decides, in writing, in the RFC.
3. A maintainer who is the RFC's author MUST NOT be the only maintainer to approve it, while there is more than one maintainer. While there is one, section 12.3 applies.
4. Silence is not consent from the public: an RFC with no outside review is accepted on the maintainers' judgement, and the RFC MUST say that it had none.

## 8. What a change must come with

### 8.1 To become Implemented

- The specification text, with the header updated to name the RFC.
- **Vectors** for every new outcome, including the refusals: at least one vector for each new refusal code or standing, and at least one for each rule that an implementation could plausibly get wrong.
- The reference implementation reproduces every vector, published and new.
- No published expectation changed (invariant 1), shown by a comparison in the pull request.

### 8.2 To become Final

- **Two independent implementations** reproduce every vector of the specification. Independent means written by different people from the published text, sharing no protocol code. Bindings to one implementation count once.
- At least one of the two is **publicly available** in source.
- Every normative reference of the specification is published. A specification whose text defers to a definition that is not public (section 10) cannot be Final.
- No open issue marks an ambiguity in it as blocking.

### 8.3 Where the existing specifications stand

Every specification published before this process is **Draft**. None is Final. [The normative audit](../governance/normative-audit-2026-10.md) says what each one lacks, and [the open questions](../governance/open-questions.md) list the RFCs that would move them.

## 9. Security and cryptography

### 9.1 What needs security review

An RFC needs security review if it touches any of: a signing input or signing domain; a digest or what it commits to; the canonical encoding; key validity, revocation or time; the trust registry or who may speak for what; a refusal that guards one of these; anything that changes what a verified result may be relied on for.

Such an RFC MUST:

- have a **Security Considerations** section that states what an adversary controls, what the change prevents, and what it does not;
- name every cryptographic primitive by a published standard, and MUST NOT define a new primitive;
- include negative vectors: inputs an adversary would construct, with the refusal each must get;
- be reviewed by at least one person other than its author who is competent to review it. The RFC names that person. If no such person reviewed it, the RFC MUST say so, and it cannot become Final.

### 9.2 What a specification may claim

A specification MUST state what its checks establish and what they cannot. A sentence that a result is "verified", "valid" or "secure" without saying what was checked, under whose keys, is a defect.

### 9.3 Vulnerabilities

A vulnerability in a specification is reported privately to the maintainers, not in a public issue. The maintainers acknowledge within 7 days and agree a disclosure date with the reporter.

A fix that changes an outcome is still a new version (invariant 2): the vulnerable version is deprecated with a public advisory that says what it does not protect against. The review period for such an RFC MAY be shortened, or run after publication, by the maintainers' written decision in the RFC. Invariant 1 is never suspended: an expectation that turns out to encode a vulnerability stays published, marked as such.

## 10. Formal semantics

1. Where a specification declares a formal definition to prevail over its text, that definition MUST be published in this repository before the specification can become Final. Until then the specification MUST say that its normative definition is not public.
2. A specification MUST distinguish what is **proved** about a definition from what is **tested** against vectors. A property is called proved only if the proof is published and names its hypotheses.
3. Where the text and the formal definition disagree, the specification's own precedence rule applies. Where the text and a published vector disagree, the vector's expectation stands for that version (invariant 1), the text is corrected, and the disagreement is recorded as an erratum in the specification.

## 11. How an accepted RFC becomes specification text

An RFC is not a specification, and specification text is never copied into an RFC. An accepted RFC is carried out by changing the specification and adding vectors. The specification's header then names the RFC, and the RFC records the specification, version and commit that implement it.

For now, specifications and vectors are written in the steward's source repository and published here by an export ([publication](../governance/publication.md)). So:

- RFCs are proposed, reviewed and decided **here**.
- The text and vectors that carry out an accepted RFC arrive here by export, in a pull request that names the RFC.
- A pull request here that edits an exported file directly is not merged as it is. Its content is taken as a proposal: an editorial fix is applied at the source, anything else follows section 4.
- The export never writes, replaces or removes `rfcs/`, `governance/`, `conformance/` or `CONTRIBUTING.md`.

Moving the specifications themselves here is a goal with stated preconditions, in the publication document. It is a change to this process and needs an RFC.

## 12. Adoption and change of this process

1. This RFC was adopted by the steward's decision. There was no process to adopt it under, and it does not pretend there was.
2. Any later change to it is a normative change and needs an RFC under it.
3. At adoption there is one maintainer. Until there is a second, that maintainer's decisions stand on the review period alone, and every RFC accepted in that time MUST say so. Adding maintainers from outside the steward is RECOMMENDED as soon as there are implementers outside it, and is done by the steward on the maintainers' proposal.

## 13. What this process does not provide

- **Neutrality.** One company stewards the protocol and decides in a tie.
- **Endorsement.** No standards body has reviewed any of this.
- **A patent policy.** Contributions are made under the repository's licenses, and nothing more is promised here.
- **Certification.** A conformance report ([`conformance/`](../conformance/README.md)) is an implementer's own statement. Nobody certifies it.

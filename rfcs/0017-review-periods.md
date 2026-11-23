# RFC 0017: Review periods

|            |                                                                        |
| ---------- | ---------------------------------------------------------------------- |
| RFC        | 0017                                                                   |
| Status     | Review                                                                 |
| Author     | Zin Nam                                                                |
| Created    | 2026-11-23                                                             |
| Affects    | RFC 0001, section 5, rule 1. No specification, vector or proof changes |
| Supersedes | Nothing                                                                |

RFC 0001 gives every RFC a public review period of at least 14 days. This RFC adds an early phase, which lasts while nobody outside the steward maintains or implements the protocol. In the early phase, an RFC that only adds is accepted as soon as a reviewer other than the author agrees, and any other RFC waits 72 hours. After the early phase, periods are set by what an RFC changes: 7 days for one that only adds, 14 days for the rest, and an early end after 72 hours when the maintainers and a reviewer agree. Review by someone other than the author is required throughout. This is for everyone who proposes or relies on a change to the protocol.

## Motivation

RFC 0001, section 5, rule 1 requires at least 14 days of public review for every RFC, whatever it changes.

The 14 days protect people who depend on the protocol from a change they could not answer in time. Today there are no such people outside the steward:

- [`governance/MAINTAINERS.md`](../governance/MAINTAINERS.md) lists one maintainer;
- every implementation that reproduces the vectors is the steward's own;
- the second implementation by other authors that milestone A of [publication](../governance/publication.md) asks for does not exist.

The protocol is in early development. Its specifications are being written as a series, each building on the one before: a ledger, a format for system models, an extension that uses both. Every step waits 14 days after its review is done, though no one outside the steward can be affected.

What actually protects the protocol is not the wait but the review. In the RFCs of November 2026, a reviewer other than the author found errors the author had missed, such as a witness that could be moved by a stolen key. This RFC keeps that review required, and shortens the wait while nothing outside the steward depends on it.

## What changes

Section 5, rule 1 of RFC 0001 is replaced. The new rule says:

**1. Review by someone other than the author.** Every RFC is reviewed in public, in its pull request, by at least one reviewer who is not its author. The reviewer states that they agree and names the commit they reviewed. An agreement counts only for that commit. A later change of substance (rule 2 of section 5) needs a new agreement. An objection raised in the pull request and not yet answered in the RFC prevents acceptance.

**2. The early phase** lasts while both of these hold:

- `governance/MAINTAINERS.md` lists no maintainer outside the steward;
- no implementation by authors outside the steward is listed as reproducing the vectors (milestone A's fourth prerequisite in `governance/publication.md`).

**3. Minimum periods.** The review period starts when the RFC enters Review and lasts at least:

| What the RFC changes                                                                                                                                                   | In the early phase                   | After it                                                       |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | -------------------------------------------------------------- |
| **Only adds.** A new specification, version or extension under a new identifier. No published outcome changes (section 6, invariant 1), and no published file changes. | None: until the agreement of rule 1  | 7 days, or 72 hours with every maintainer's and the agreement  |
| **Changes a published outcome**, or deprecates                                                                                                                         | 72 hours, or less with the agreement | 14 days, or 72 hours with every maintainer's and the agreement |
| **Changes this process**                                                                                                                                               | 72 hours                             | 14 days                                                        |
| **A security fix**, under section 9.3                                                                                                                                  | as section 9.3 says                  | as section 9.3 says                                            |

When it is unclear which row applies, the longer one does, as in section 4. "The agreement" is the one of rule 1.

**4. The end of the early phase.** A pull request that lists the first outside maintainer or implementation records the day the early phase ends. From that day the column "After it" applies, without a further RFC. An RFC in review on that day keeps the minimum it started with.

**5. RFCs in review** when this RFC is accepted keep their start date. The new minimum applies to them from acceptance.

Rule 2 of section 5 (no change of substance without restarting the period) is unchanged. A restart restarts the minimum that applies.

What stays as it is:

- the compatibility invariants of section 6, among them that a published expectation never changes, so a change to a published outcome still needs a new identifier;
- the decision of section 7, written in the RFC with its reasons and the objections answered.

The decision states which row applied, and the agreement it relied on.

## Outcomes that change

None. No specification, version, vector, example or proof changes. What changes is how long an RFC waits before it can be decided.

## Compatibility

- **Contributors** see an RFC that only adds decided as soon as its review is agreed, while the early phase lasts.
- **Implementers** see no change in any published file. A published expectation still never changes (section 6), whatever the period.
- **Once others depend on the protocol,** the longer periods apply by rule 4, without a further RFC.

## Vectors

None. This RFC changes the process, not a specification.

## Security considerations

- **A rushed change.** No RFC is decided without a reviewer other than the author agreeing to a named commit. Rule 2 of section 5 stops an RFC from changing after agreement, and section 6 stops any change, however fast, from altering a published expectation.
- **A reviewer who agrees too easily.** In the early phase the agreement is the only gate for an RFC that only adds. Such an RFC adds a new identifier, which nothing yet depends on, so a mistake in it costs a new version, not a broken implementation.
- **Self-approval.** The author cannot be the reviewer of rule 1. Section 7, rule 3 still forbids an author being the only maintainer to approve while there is more than one.
- **A short period that outlives its reason.** Rule 4 ends the early phase when the first outside maintainer or implementation appears. The condition is checked against files in this repository, not against anyone's judgement.
- **Public visibility.** An RFC that only adds can be decided within hours of entering Review. Anyone watching the repository still sees every RFC, its review and its decision, and can ask for reconsideration under section 5, rule 5.

## Formal semantics

Nothing here is formal.

## Alternatives

- **Keep 14 days for everything.** It protects no one today and delays every step of the series.
- **7 days for RFCs that only add, 14 for the rest, even now** (the first version of this RFC). It still waits a week for review already done.
- **No minimum and no review in the early phase.** Fastest, but review is what has caught real errors; without it the process would be the author's word.
- **Change the process by the steward's decision,** as RFC 0001 was adopted (section 12, rule 1). Faster, but it changes the process outside the process, which section 12, rule 2 rules out.
- **An early phase with no end condition.** It would stay short once others depend on the protocol.

## Open questions

None.

## Decision

Pending. Under the current rule, the review period runs from 2026-11-23 to at least 2026-12-07. This version replaces the one first opened, on the same day. There is one maintainer, so under RFC 0001, section 12.3, the decision will stand on the review period alone, and will say so.

## Implementation

On acceptance, section 5, rule 1 of RFC 0001 is replaced by rules 1 to 5 above, in a pull request that names this RFC.

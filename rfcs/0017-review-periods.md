# RFC 0017: Review periods

|            |                                                                        |
| ---------- | ---------------------------------------------------------------------- |
| RFC        | 0017                                                                   |
| Status     | Review                                                                 |
| Author     | Zin Nam                                                                |
| Created    | 2026-11-23                                                             |
| Affects    | RFC 0001, section 5, rule 1. No specification, vector or proof changes |
| Supersedes | Nothing                                                                |

RFC 0001 gives every RFC a public review period of at least 14 days. This RFC sets the period by what an RFC changes: 7 days for an RFC that only adds, 14 days for one that changes a published outcome. It lets any review end after 72 hours when the maintainers and a reviewer other than the author agree. These shorter periods hold only while nobody outside the steward maintains or implements the protocol. This is for everyone who proposes or relies on a change to the protocol.

## Motivation

RFC 0001, section 5, rule 1 requires at least 14 days of public review for every RFC, whatever it changes.

The 14 days protect people who depend on the protocol from a change they could not answer in time. Today there are no such people outside the steward:

- [`governance/MAINTAINERS.md`](../governance/MAINTAINERS.md) lists one maintainer;
- every implementation that reproduces the vectors is the steward's own;
- the second implementation by other authors that milestone A of [publication](../governance/publication.md) asks for does not exist.

The steward is the only party a change can affect, and the review that actually happens, by a reviewer other than the author, often finishes within days.

The cost of the fixed period is real. A new specification that changes nothing existing, such as a ledger format or an extension, waits 14 days after its review is done. A series of RFCs that build on each other waits 14 days at each step.

The fixed period is right once others depend on the protocol, and this RFC keeps it for then.

## What changes

Section 5, rule 1 of RFC 0001 is replaced. The new rule says:

**1. The review period** is public, in the RFC's pull request, and lasts at least:

| What the RFC changes                                                                                                                                                   | Minimum             |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| **Only adds.** A new specification, version or extension under a new identifier. No published outcome changes (section 6, invariant 1), and no published file changes. | 7 days              |
| **Anything else.** A change to a published outcome, a deprecation, a change to this process.                                                                           | 14 days             |
| **A security fix**, under section 9.3                                                                                                                                  | as section 9.3 says |

When it is unclear which row applies, the longer one does, as in section 4.

**2. Early end.** Any review period may end after 72 hours when, in the pull request:

- every maintainer states that they agree; and
- at least one reviewer who is not the author states that they agree, and names the commit they reviewed.

An agreement counts only for the commit it names. A later change of substance (rule 2 of section 5) needs new agreements. An objection raised in the pull request and not yet answered in the RFC prevents an early end.

**3. While it applies.** Rows one and two of the table and the early end apply only while both of these hold:

- `governance/MAINTAINERS.md` lists no maintainer outside the steward;
- no implementation by authors outside the steward is listed as reproducing the vectors (milestone A's fourth prerequisite in `governance/publication.md`).

From the day either stops holding, every review period is at least 14 days, except a security fix under section 9.3. A pull request that lists the first outside maintainer or implementation records that day. An RFC in review on that day keeps the period it started with.

**4. RFCs in review** when this RFC is accepted keep their start date. The new minimum applies to them from acceptance.

Rule 2 of section 5 (no change of substance without restarting the period) is unchanged. A restart restarts the minimum that applies.

The RFC states in its decision which row applied, and whether the review ended early, with the agreements.

## Outcomes that change

None. No specification, version, vector, example or proof changes. What changes is how long an RFC waits before it can be decided.

## Compatibility

- **Contributors** see shorter waits for RFCs that only add, and for any RFC whose review is complete and agreed.
- **Implementers** see no change in any published file. A change to a published outcome still waits 14 days.
- **Once others depend on the protocol,** the process returns to 14 days for everything, by rule 3, without a further RFC.

## Vectors

None. This RFC changes the process, not a specification.

## Security considerations

- **A rushed change.** The shorter periods apply only to RFCs that change no published outcome, or to reviews that a reviewer other than the author has completed and agreed to, with the commit named. A change to a published outcome waits 14 days unless reviewed and agreed. Rule 2 of section 5 still stops an RFC from changing after agreement.
- **Self-approval.** The early end needs a reviewer other than the author. Section 7, rule 3 still forbids an author being the only maintainer to approve while there is more than one.
- **A short period that outlives its reason.** Rule 3 ends the shorter periods when the first outside maintainer or implementation appears. The condition is checked against files in this repository, not against anyone's judgement.

## Formal semantics

Nothing here is formal.

## Alternatives

- **Keep 14 days for everything.** It protects no one today and delays additive work.
- **Change the process by the steward's decision,** as RFC 0001 was adopted (section 12, rule 1). It would be faster, but it would change the process outside the process, which section 12, rule 2 rules out.
- **Shorter periods with no end condition.** They would stay short once others depend on the protocol, when the reason for them is gone.
- **Early end with the maintainers' agreement alone.** With one maintainer, who is often the author, that is no review at all.

## Open questions

None.

## Decision

Pending. Under the current rule, the review period runs from 2026-11-23 to at least 2026-12-07. There is one maintainer, so under RFC 0001, section 12.3, the decision will stand on the review period alone, and will say so.

## Implementation

On acceptance, section 5, rule 1 of RFC 0001 is replaced by rules 1 to 4 above, in a pull request that names this RFC.

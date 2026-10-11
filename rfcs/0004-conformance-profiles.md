# RFC 0004: Conformance profiles

|            |                                                                                               |
| ---------- | --------------------------------------------------------------------------------------------- |
| RFC        | 0004                                                                                          |
| Status     | Draft                                                                                         |
| Author     | Zin Nam                                                                                       |
| Created    | 2026-10-12                                                                                    |
| Affects    | What "conforms" means in [`conformance/`](../conformance/README.md). No specification changes |
| Supersedes | Nothing                                                                                       |

Seven named sets of corpus parts that an implementation can claim as a whole, so that "implements WVP" has a small number of exact meanings. No specification, vector or outcome changes.

## Motivation

Today an implementation conforms to a specification, and a specification is not what anyone uses. A relying party that asks "can this verifier check the package I was sent?" needs a package verifier, which needs evidence statements, the contract language and the canonical encoding, and needs neither claim registration nor work relations. The eight specifications are layered so that this is possible ([architecture](../governance/architecture.md)); nothing names the useful subsets, so each implementation describes its coverage in its own words, and two descriptions cannot be compared.

The boundaries below are taken from that layering and from what a party does, not from what any implementation happens to support. The first run of the public report shows it: no public implementation reproduces every profile, and the one reason a package verifier falls short of the `wvp-0.2` profile is a single contract-language case.

## What changes

A **profile** is a named set of parts of the corpus, closed under the dependencies of the architecture map. An implementation **reproduces a profile** when it reproduces every case of every part in it, comparing the whole expectation. Anything less is **partial**, reported part by part as today. There are no levels, and a profile contains no optional part.

| Profile                          | What a party does with it                                            | Parts (as named in `conformance/corpus.json`)                                                  |
| -------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **Canonical encoding**           | Computes the bytes every digest and signature is over                | Canonical bytes and digests                                                                    |
| **Contract evaluation**          | Evaluates a Work Contract Language 1 contract against an environment | Canonical; contract cases; generated differential cases                                        |
| **Evidence authentication**      | Checks a source's statements, chains of them, and their admission    | Canonical; statements; chains; admission                                                       |
| **Offline verification, 0.1**    | Verifies a `wvp-0.1` package under a relying party's registry        | Canonical; statements; `wvp-0.1` packages                                                      |
| **Offline verification, 0.2**    | Verifies a `wvp-0.2` package, with expectations                      | Canonical; statements; contract cases and differential cases; `wvp-0.2` packages; expectations |
| **Claim registration and audit** | Checks registrations, a registry's log, audits, disputes and heads   | Canonical; work-unit identity; the seven parts of claim registration                           |
| **Work history and relations**   | Reads what authorities say about the records of one unit of work     | Canonical; statements; readings                                                                |

Three rules:

1. **A profile is claimed for verifying.** `produce` remains a separate capability, reported per specification: an implementation produces objects of a specification when a verifier that reproduces the profile containing it accepts them. Until a specification has such a verifier in public, a produce claim says which verifier accepted the objects.
2. **A version is a profile of its own.** Verifying `wvp-0.1` and verifying `wvp-0.2` are different claims, because the versions are never interchanged.
3. **A new specification or version comes with its profile**, or says which existing profile gains its parts. Adding a part to a profile is done by the RFC that adds the part.

The map of the corpus carries the profiles, and the public report states, for each implementation run here, whether it reproduces each one.

## Outcomes that change

None. This RFC defines names for sets of existing cases.

## Compatibility

A conformance report keeps its six parts and may add the profiles it reproduces. A report that claims a profile must reproduce every case in it, which is a stricter statement than any implementation's present documents make; none of them becomes false, and several become "partial" where they read as complete.

## Vectors

None are added. Each profile is tested by the parts it names.

## Security considerations

This RFC touches nothing listed in RFC 0001, section 9.1. It bears on security in one way: a name such as "offline verification" will be read as assurance. A profile says an implementation agrees with the corpus on a set of cases. It does not say the implementation is correct elsewhere, was reviewed, or is safe to rely on, and a statement that an implementation "conforms to the Core profile" without the corpus commit and the implementation's version is a defect of the kind RFC 0001, section 9.2 describes.

## Formal semantics

Nothing is proved or needs to be.

## Alternatives

- **One profile, everything.** No implementation would reproduce it, and a package verifier has no use for a registry's log.
- **Levels** (bronze, silver). Levels invite reading a higher one as safer. The profiles are different jobs, not more or less of one.
- **A profile per specification.** That is today's arrangement, and it does not answer the relying party's question.
- **Folding evidence authentication into offline verification.** A source or a gateway authenticates statements and chains without ever handling a package, and a package verifier does not need chains: `wvp-0.2` does not check a chain's continuity.
- **Leaving heads out of the registration profile** because no public implementation checks them. That would draw the boundary around one implementation's gap.

## Open questions

1. **Should evidence production be a profile?** It has no vectors of its own: a producer is tested by a verifier accepting what it makes.
2. **Should offline verification 0.2 include chains?** It does not, because the version does not check them.
3. **Names.** "Offline verification" may promise more than "package verification".

## Decision

Not made. The review period has not started.

## Implementation

The profiles are in `conformance/corpus.json` and in the public report, marked as proposed.

# Contributing

WVP changes in public, under [RFC 0001](rfcs/0001-standards-process.md). You need no affiliation and no permission to take part.

## If you found something unclear, or two readings of one sentence

Open an issue. This is the most useful contribution there is. Say:

- which specification and section;
- the input, as exactly as you can;
- the readings you see, and which one your implementation took;
- whether a published vector decides it.

If no vector decides it, the answer becomes a clarification with a new vector. If one does, or implementations already differ, it needs an RFC.

## If you want to change the protocol

Read RFC 0001, section 4, to see which kind of change it is. For a normative change, copy [`rfcs/0000-template.md`](rfcs/0000-template.md) and open a pull request. Start with the problem: an RFC that shows a real failure is easier to accept than one that shows a better design.

Three things no RFC can do (RFC 0001, section 6): change a published expectation, change an outcome without a new version, or make a verifier trust something because the object under verification says so.

## If you implemented a specification

Tell us what you reproduced, by a pull request that adds `conformance/reports/<your-implementation>.md` ([how](conformance/README.md)). Partial support is welcome and has a defined way of being reported. Every place where you had to guess is an issue worth opening.

## If you found a vulnerability

Do not open a public issue. Report it privately to the maintainers ([`governance/MAINTAINERS.md`](governance/MAINTAINERS.md)), through this repository's private vulnerability reporting. RFC 0001, section 9.3, says what happens next.

## Where a pull request can land

- `rfcs/`, `governance/`, `conformance/` and this file are written here. Pull requests to them are reviewed and merged here.
- Specifications (`protocols/`, `docs/spec/`), vectors and examples (`test-vectors/`), `README.md` and `PROVENANCE.md` are exported from the steward's source repository. A pull request that edits them is not merged as it is, because the next export would overwrite it. It is taken as a proposal and carried out at the source, with credit. [Publication](governance/publication.md) explains why, and what would change it.

## Licenses

Prose (every Markdown file) is licensed under CC BY 4.0, and everything else under the Apache License 2.0 ([`LICENSE`](LICENSE)). By contributing you agree that your contribution is licensed the same way. There is no contributor agreement and no patent policy beyond those licenses.

## Conduct

Argue about the protocol, not about people. Say what you checked and what you did not.

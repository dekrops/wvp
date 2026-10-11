# Proposing vectors with public tooling

Informative. How anyone can build a candidate vector, check it against a public implementation, and propose it, without the implementation that generates the published corpus.

A proposed vector is not a vector. It becomes one when the change it belongs to is carried out ([RFC 0001](../rfcs/0001-standards-process.md), section 8.1). Until then it lives beside its RFC, under `rfcs/NNNN/vectors/`, never under `test-vectors/`.

## 1. Write a generator, not files

A proposal comes with the program that writes it: `rfcs/NNNN/generate.py`.

- **Standard library only**, so that running it needs nothing but Python.
- **Deterministic.** The same files, byte for byte, every time. No clock, no random value. Keys come from the seeds the corpus publishes.
- **`--check`** fails if the files beside it are not what it would write. This repository's CI runs it for every RFC.
- **It starts from published vectors** and changes one thing in each, and it asserts that it reproduces the published object (a signature, a commitment) before it changes anything. That is what shows its own encoding and signing are right.
- **The format is the corpus's**, so that an implementation's existing harness runs the result. A new file is a new vector. A file named `<name>.additions.json` holds lists of cases to append to the lists of the published `<name>.json`.

Cases that need a signature no library will make (an unreduced S, a point of small order) need the arithmetic written out. RFC 0002's generator has an implementation of RFC 8032 for that purpose, which later generators may copy.

## 2. Run it through an implementation you did not write

```sh
python3 conformance/tools/conformance.py try \
  --proposal rfcs/NNNN/vectors --implementation rust --source <a checkout of verified-cli>
```

Each proposed case is placed beside the published corpus in a temporary copy, and the implementation is asked to reproduce the part it belongs to. The answer for each case is one of:

- **AGREES**: an implementation written by someone else reaches the proposed outcome. This is the evidence a proposal needs.
- **DIFFERS**: it does not. Either the proposal is wrong, or the implementation is, or the specification allows both. All three are worth an issue, and none is settled by changing the expectation until it agrees.
- **NOT RUN**: no implementation is run against that part. The proposal rests on its author alone, and its RFC must say so.

## 3. What a proposal must not rest on

- **Its generator alone.** A generator that both signs and states the expected outcome agrees with itself. At least one implementation that shares no code with it must reproduce each case, or the RFC names the cases for which none does.
- **The implementation that will be changed to match.** An expectation taken from an implementation's present behaviour proves nothing about that implementation.
- **A changed published vector.** A proposal adds. The `unchanged` check refuses anything else.

## 4. What public tooling cannot do yet

- **Valid packages with new shapes.** A generator can alter a published package and recompute its commitment. Producing an accepted package of a new version needs an implementation of that version; `verified-cli` issues `wvp-0.2` packages and nothing later.
- **Expected reports.** Where a vector states a whole report, a decision with every requirement's value, the expectation has to come from an evaluator. For Work Contract Language 1 there are two public ones (Rust and Lean); a case on which they agree is well supported.
- **Claim registration heads and work relations by a second implementation.** One public implementation, or none, is run against those parts ([what is checked](ci.md)).

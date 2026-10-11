# RFC 0002: Inputs every verifier refuses alike

|            |                                                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------------------------------ |
| RFC        | 0002                                                                                                               |
| Status     | Draft                                                                                                              |
| Author     | Zin Nam                                                                                                            |
| Created    | 2026-10-12                                                                                                         |
| Affects    | `verified-json-v1`, `verified-evidence-statement-v1`, `wvp-0.1`, `wvp-0.2`. A revision of each: no version changes |
| Supersedes | Nothing                                                                                                            |

Six rules for inputs that the specifications leave open and that two verifiers, written separately, treat differently today: which Ed25519 signatures verify, a member written twice, a time that is no instant, an integer out of range, a trust registry that is not well-formed, and two refusal codes of a package. Each comes with vectors. No published vector changes, and no object an honest producer writes is refused.

## Motivation

A relying party runs one verifier. The protocol's promise is that any other verifier would have told it the same. For the inputs below it would not.

32 cases were built for this RFC ([`0002/generate.py`](0002/generate.py)), each a published vector with one thing changed, signed with the published test keys. They were run through `verified-cli` `v0.1.4` (Rust, public) and through the steward's JavaScript verifier (not public; its results are reported here because the disagreement is the evidence). **In 21 of the 32, the two give different answers.** In 19 of those, one of them accepts, or uses, what the other refuses. The table groups them, and its second row is a further experiment that is not among the vectors:

| Input                                                                            | Rust `v0.1.4`         | JavaScript                          |
| -------------------------------------------------------------------------------- | --------------------- | ----------------------------------- |
| A registry holding a public key of small order                                   | refuses the registry  | uses it                             |
| A statement signed `(neutral element, 0)` under that key, which anyone can write | —                     | **accepts**                         |
| A signature whose R is the neutral element, under an honest key                  | `SIGNATURE_INVALID`   | **accepts**                         |
| A signature in unpadded, URL-safe or stray-bit base64                            | `SIGNATURE_INVALID`   | **accepts**                         |
| A statement with a member written twice                                          | refuses               | **accepts**, taking the last        |
| `observedAt` of `2026-02-30T10:00:00Z`, or of hour 24                            | `MALFORMED`           | **accepts**                         |
| `chain.sequence` of -1                                                           | **accepts**           | **accepts**                         |
| `chain.sequence` of 2^53                                                         | **accepts**           | `MALFORMED`                         |
| A registry entry with `revokedAt` misspelt `revokedAT`                           | refuses the registry  | uses it: **the key is not revoked** |
| A registry key in unpadded base64, or a `validFrom` not in canonical spelling    | refuses the registry  | uses it                             |
| A manifest entry with the right digits and the algorithm name `sha-512`          | `COMPONENT_DIGEST`    | **accepts** the package             |
| A component whose `path` is a number                                             | `MALFORMED_COMPONENT` | `COMPONENT_SET`                     |
| `packageVersion` of 2^53 + 1                                                     | `UNSUPPORTED_VERSION` | `NOT_CANONICAL`                     |

None of these is decided by a published vector. Most are among the 43 readings `verified-cli` recorded while implementing from the text ([#8](https://github.com/dekrops/wvp/issues/8) to [#12](https://github.com/dekrops/wvp/issues/12)); three were not known (a sequence below zero is accepted by both; a small-order R; the cofactor).

The second row is the one that matters most. Evidence Statement v1 asks for a signature "verified strictly by the platform library". Under a library that follows RFC 8032 and no more, a registry entry whose key is the neutral element makes every statement attributed to that key verify, signed by anyone. The relying party wrote that registry, so this is not a forgery against an honest configuration. It is a way for a signer to hand over a key under which it can later deny everything, and the two verifiers disagree on whether such a key is usable.

## What changes

Each rule is stated so that it can be implemented from this text and RFC 8032, RFC 8410 and RFC 4648. Where a rule decides a case the text already implies, it says so.

### 1. Which signatures verify

For every Ed25519 signature the four specifications define (a statement's, and an issuer's over a decision), with `encoded` the JSON string, `A` the 32 octets of the registered public key and `M` the signing input:

1. `encoded` is the base64 encoding of RFC 4648 section 4, with padding, of exactly 64 octets, and encoding those octets again gives `encoded`.
2. `R` is the first 32 octets and `S` the last 32, read as a little-endian integer. `S` is less than the group order `L`.
3. `R` decodes as RFC 8032 section 5.1.3 defines, which refuses `y ≥ p` and refuses `x = 0` with the sign bit set. `[8]R` is not the neutral element.
4. `[S]B = R + [k]A`, with `k = SHA-512(R ‖ A ‖ M)` reduced modulo `L`. This is the equation of RFC 8032 section 5.1.7 **without** the factor 8. RFC 8032 allows either form; they differ on some inputs, and this rule fixes one.

A signature that fails any of the four does not verify, and the refusal is the one the specification gives for a signature that does not verify (`SIGNATURE_INVALID` for a statement, `ISSUER_SIGNATURE_INVALID` for a decision), at the step where signatures are checked. The phrase "verified strictly by the platform library" is replaced by this rule.

`A` is constrained by rule 5: a registry never holds a key that fails to decode or has small order. An implementation of signature verification as a function MUST also refuse such a key, so that the function has one result whatever registry it is called under.

### 2. A member written twice

A JSON text in which an object has two members whose names are equal, after escape sequences are resolved, is not the encoding of any value in `verified-json-v1`. Wherever a specification requires canonical text, such a text is refused with that specification's code for text that is not canonical or not well-formed: `NOT_CANONICAL` for a package (step 1), `MALFORMED` for a statement (step 1). It does not matter whether the two values are equal.

This replaces "duplicate keys are outside the object model".

### 3. Times that are no instant

A clarification: the text already says a time is refused if "its re-encoding differs from its received form". A string is the canonical spelling of an instant only if its year, month and day are a date of the proleptic Gregorian calendar, its hour is 00 to 23, its minute 00 to 59 and its second 00 to 59. There is no second 60 and no hour 24. Anything else is refused as a time not in canonical spelling is.

### 4. Integers

- `verified-json-v1` allows an integer of any size, and a published vector says so. A verifier MUST NOT refuse a text as not canonical because of the size of an integer in it. A limit on the size of an input is a resource limit, which is [open question C5](../governance/open-questions.md) and not this RFC.
- `chain.sequence` of a statement is an integer from 0 to 2^53 - 1. Outside that range the statement is `MALFORMED`. The bound is the largest integer every JSON implementation represents exactly (RFC 8259, section 6).
- `wvp-0.1` already says "integers fit 32 bits" for the objects it defines. That stands.

### 5. The trust registry

Today the registry's format is one paragraph and the vectors' `registry` members. This rule states it.

A registry is an object with exactly one member, `keys`, an array of entries. An entry has exactly the members `algorithm`, `issuer`, `keyId`, `publicKey`, `sources`, `tenant` and `validFrom`, and may have `validUntil` and `revokedAt`; either of those absent means what `null` means. Any other member makes the registry unusable. Times are in canonical spelling (rule 3). No two entries have the same `keyId`, and no two the same `publicKey`.

For an entry whose `algorithm` is `Ed25519`, `publicKey` is the base64 of RFC 4648 section 4, with padding, of the 44 octets of an RFC 8410 `SubjectPublicKeyInfo`, and encoding those octets again gives the same string. The 32 octets of the key decode as RFC 8032 section 5.1.3 defines, and `[8]A` is not the neutral element.

**A verifier given a registry that is not usable checks nothing under it.** It reports that the registry is not usable, and reports no outcome for the object: neither a refusal nor a result without a registry. This is a fault in the relying party's configuration, which no object can cause, so it has no refusal code.

### 6. Two refusals of a package

- **A digest is an algorithm name and digits.** Step 5 compares a component's digest with its manifest entry. They are equal when both members are. An entry with the right digits and another algorithm name is `COMPONENT_DIGEST`.
- **A member of the wrong type is step 3.** `MALFORMED_COMPONENT` at step 3 covers the members section 2 lists and their types: a `path` that is not text is refused there, before step 4 compares paths.

## Outcomes that change

None that a specification or a published vector defines.

| Rule | Kind under RFC 0001, section 4                                                                              |
| ---- | ----------------------------------------------------------------------------------------------------------- |
| 1    | Normative. It replaces a reference to an unnamed library by a definition. Security review, section 9.1      |
| 2    | Normative. The text says the case is undefined                                                              |
| 3    | Clarification. The re-encoding rule already refuses these; the cases have no vector                         |
| 4    | Clarification for the size of integers (a published vector decides it); normative for the range of sequence |
| 5    | Normative. It defines a format that was implied. Security review                                            |
| 6    | Clarification. The published implementations differ, so it is decided here and not by an issue alone        |

Every input these rules decide had no defined outcome, and every published vector keeps its expectation: the 976 cases of the corpus are reproduced unchanged by an implementation that already follows 29 of the 32 proposals. So each specification is revised, not versioned (invariant 4), and its header records the revision.

## Compatibility

- **A producer** changes nothing. Every object in the published corpus that is accepted today is accepted under these rules, and no library signs with a small-order R, an unreduced S or lenient base64 unless it is made to.
- **A relying party** whose registry has a member this RFC does not list, a key in lenient base64 or a time not in canonical spelling finds that its registry is refused, where one verifier used to read it. That is the point: one of those members may be a misspelt revocation.
- **A verifier** implements the rules. Measured against the proposals: `verified-cli` `v0.1.4` differs on 3 of 32 (it accepts both sequence numbers out of range, and its statement interface takes parsed JSON and so reports no code for a duplicated member). The steward's JavaScript verifier differs on 21 of 32. A verifier on a library that implements RFC 8032 and no more needs four additions for rule 1: the canonical-base64 check, `S < L` if the library lacks it, the two small-order checks, and nothing for the equation if the library uses the form without the factor, which the common ones do.

## Vectors

[`0002/vectors`](0002/vectors), written by [`0002/generate.py`](0002/generate.py) in the format of the published corpus, so that an implementation's existing harness runs them. They are proposals: they are not in `test-vectors/`, and become vectors when this RFC is implemented.

| Part                                | Cases | What they pin                                                                                                                                                                |
| ----------------------------------- | ----: | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `evidence-statement/v1/must-reject` |     8 | S not reduced; R of small order; R not canonically encoded; a signature that satisfies only the cofactored equation; three base64 spellings; 63 octets                       |
| `evidence-statement/v1/invalid`     |     6 | A member twice; three times that are no instant; a sequence of -1 and of 2^53                                                                                                |
| `wvp/v0.2`                          |     4 | A member twice; the algorithm name; a path that is a number; a version beyond 2^53                                                                                           |
| `trust-registry/v1` (a new part)    |    10 | One usable registry without the optional members; nine that are not: three keys of small order or bad encoding, two key encodings, an unknown member, two duplicates, a time |
| `canonical-hash-v1.json`, `invalid` |     4 | A member twice: same value, other value, nested, and equal only after an escape is resolved                                                                                  |

The registry vectors state `accept` and no code, as the invalid cases of the canonical encoding do.

**How they were checked.** The generator signs with an implementation of RFC 8032 written for it, and asserts that it reproduces a published statement's signature and a published package's commitment before it changes anything. Each case was then run through `verified-cli`'s own conformance harness beside the published corpus, and through the JavaScript verifier. No case rests on the generator's word alone: for each, at least one implementation that shares no code with it agrees with the proposed outcome, except the two sequence cases, which rest on rule 4 and on which the two verifiers split.

Not covered by a vector, and said so: `x = 0` with the sign bit set, and a key or R that is canonically encodable only as `y ≥ p` and is not of small order. Constructing a signature under the second needs a discrete logarithm.

## Security considerations

**What an adversary controls.** Every byte of a statement and a package, including the signature's spelling. For rule 5, a signer chooses the key it asks a relying party to register.

**What the rules prevent.**

- _A key under which anyone can sign._ With `A` of small order, `(R, S) = (neutral, 0)` and its seven siblings satisfy the equation for every message. Rule 5 keeps such a key out of a registry and rule 1 refuses it in the function.
- _Two signatures for one statement._ `S` and `S + L` verify alike without rule 1.2, and a lenient base64 decoder accepts several strings for one signature. A statement's digest covers the statement and not its signature, so this does not change a digest; it does mean that two different signed texts are "the same statement", which breaks any comparison of signed statements by bytes. Rules 1.1 and 1.2 leave one spelling.
- _Verifiers that split on a crafted signature._ The cofactored and the cofactorless equation disagree for a key with a component of small order. A signer holding such a key can write a statement that one relying party accepts and another refuses. Rule 1.4 fixes the equation.
- _A revocation that is silently not applied._ Rule 5 refuses a registry with a member it does not define.
- _A manifest that names one algorithm and is checked under another_ (rule 6). With one algorithm in the protocol this is harmless today, and it is the confusion a second algorithm would turn into an attack.

**What they do not prevent.** A relying party registering a key whose holder is dishonest, or a well-formed key the signer shares with others. Nothing here authenticates time, completeness, or a claim. Rule 1.3's refusal of a small-order R is not needed for unforgeability; see the open questions.

**Primitives.** Ed25519 as RFC 8032, SHA-512 and SHA-256 as FIPS 180-4, base64 as RFC 4648 section 4, the key structure of RFC 8410. No primitive is defined here. Rule 1 selects, among the behaviours RFC 8032 permits, the one also described as strict verification in the literature on Ed25519's variants.

**Review.** RFC 0001, section 9.1, requires review by someone other than the author who is competent to give it. **No such person has reviewed this RFC yet.** It cannot become Final until one has, and is named here.

## Formal semantics

Nothing is proved. The Lean models assume signature checking (`Statement.authentic`) and do not model encodings, so these rules sit below what is modelled. They are tested by vectors only.

## Alternatives

- **Refuse lenient base64 at step 1, as `MALFORMED`.** The text can be read that way: `encoded` is described under structure. It was not chosen because the two verifiers already agree that 63 octets are `SIGNATURE_INVALID`, a signature's octets are interpreted only when it is verified, and a refusal at step 10 keeps `UNKNOWN_KEY` reachable for a statement whose signature is also misspelt.
- **Give an unusable registry a refusal code.** A code would make the registry's fault look like a property of the object, and would need a place in each order of checks. Reporting no outcome keeps the two apart.
- **Refuse a small-order key when a signature under it is checked, and load the registry.** Then a registry holds a key that can never verify anything, silently. Refusing the registry tells the relying party.
- **Adopt the cofactored equation** (as ZIP 215 does). It is the form that is consistent under batch verification. It was not chosen because both verifiers and the libraries they rest on use the form without the factor, so choosing the other would change what verifies in every implementation for no case that is known to need it.
- **A 64-bit bound for `chain.sequence`.** One implementation cannot represent it. 2^53 - 1 statements in one stream is not a limit anyone reaches.
- **`MALFORMED_COMPONENT` for the algorithm name.** Defensible. `COMPONENT_DIGEST` needs no new shape rule: a digest is two members and they are compared.

## Open questions

1. **Small-order R** (rule 1.3). Refusing it is not needed to prevent forgery. It is proposed because two widely used strict verifiers refuse it, so that "strict" has one meaning, and the cost is one comparison. A reviewer may prefer to drop it.
2. **The other signatures of the family.** Claim registration and work relation sign with Ed25519 too. This RFC's vectors cover statements. The rule should be applied to them by the same revision or the next, with vectors of their own.
3. **A completeness statement observed before 1970** ([#10](https://github.com/dekrops/wvp/issues/10)): floor or truncation. Left open because no producer writes such a time and the fix deserves a vector that needs a signed package.
4. **Whether a registry with an entry of another `algorithm` is usable.** This RFC leaves such an entry's `publicKey` uninterpreted, as the published vector `unsupported-algorithm` implies.
5. **Resource limits** (C5) and **the format of vector files** (C4), which the new `trust-registry/v1` part adds a shape to.

## Decision

Not made. The review period of RFC 0001, section 5, has not started.

## Implementation

Not implemented. To carry it out: the text of the four specifications at the source, the vectors of `0002/vectors` moved into `test-vectors/` by export, and the reference implementation reproducing them.

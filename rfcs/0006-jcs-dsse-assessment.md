# RFC 0006: Evaluate JCS and DSSE for future WVP formats

|            | |
| ---------- | --- |
| RFC        | 0006 |
| Status     | Draft |
| Author     | Zin Nam |
| Created    | 2026-10-15 |
| Affects    | Design of future canonicalization and signature-envelope versions; no existing protocol changes |
| Supersedes | Nothing |

Propose a bounded compatibility study before extending WVP's custom canonical JSON and signature envelopes. Compare RFC 8785 JCS and DSSE against explicit WVP requirements, retain existing bytes and verification behavior, and publish a measured adopt/defer/retain decision for each layer separately. Accepting this RFC would authorize that study, not a wire-format migration.

## Motivation

WVP's distinct responsibility is to bind an agreed definition of completed work to admitted evidence and a reproducible decision. It also maintains lower-level interoperability rules: `verified-json-v1`, purpose-prefixed signing inputs and custom signature objects. Each independent implementation must reproduce them, including parsing boundaries.

This is an interoperability and maintenance question, not evidence that custom formats are intrinsically unsafe or that switching envelopes fixes the known trust gaps. No new vulnerability is claimed here.

The current [canonicalization specification](../protocols/canonical-json/v1/SPEC.md) explicitly differs from JCS. [Evidence Statement v1](../docs/spec/evidence-statement-v1.md) signs a domain prefix followed by canonical statement bytes using Ed25519. A standard library cannot replace either component without examining compatibility.

Related work:

- [RFC 0002](0002-inputs-every-verifier-refuses-alike.md) proposes clarification of duplicate members, signature acceptance and other verifier disagreements. It is a draft, not an already deployed guarantee.
- [RFC 0003](0003-wvp-0.3.md) proposes signed claims, bound completeness and explicit relying-party expectations. Neither JCS nor DSSE supplies these semantics.
- [Open questions](../governance/open-questions.md) C3 and C8 concern signature/parser strictness and the relationship to JCS.
- Specifications and vectors are currently exported from the platform repository. This RFC lives here; any later implementation/specification changes must follow the source/export process.

## What changes

Only the design process: produce a reproducible comparison and record two independent decisions. No runtime dependency, new signature algorithm, envelope identifier or canonicalization identifier is selected by this RFC.

### 1. Separate the layers

| Layer | Current responsibility | Candidate | What the candidate does not supply |
| --- | --- | --- | --- |
| Canonical bytes | Stable bytes for content digests and signatures | RFC 8785 JCS with an explicit WVP input profile | Work semantics, schemas, trust policy |
| Signature envelope | Binding a payload to a purpose and signatures | DSSE payload type and pre-authentication encoding (PAE) | Signer authorization, tenant isolation, authenticated time, completeness |
| Work verification | Admission, typed predicates, three-valued evaluation, result binding | Keep WVP/Work Contract Language semantics | Not replaced by either candidate |

DSSE signs exact payload bytes and a payload type through PAE; it does not require JSON canonicalization. JCS can remain useful for content addressing even when an envelope signs exact bytes. Evaluate JCS-only, DSSE-only and their combination rather than treating them as one migration.

### 2. JCS compatibility study

Use RFC 8785 itself as the target, not a bespoke serializer described as JCS-compatible.

| Area | Current `verified-json-v1` | JCS / assessment requirement |
| --- | --- | --- |
| Property order | Recursive UTF-16 code-unit ordering | Shared design; verify supplementary-character cases |
| Numbers | Arbitrary-size integral values, plain decimal; no rounding | ECMAScript/IEEE-754 serialization; arbitrary exact integers are not interchangeable |
| DEL and C1 controls | U+007F–U+009F escaped | JCS leaves these characters unescaped; bytes and hashes differ |
| Duplicate members | Base specification leaves parsing open; RFC 0002 proposes refusal | JCS input constraints prohibit duplicates; reject before parser information is lost |
| Unicode | Scalar values, no normalization | Verify invalid-surrogate refusal and preservation of valid text |
| Accepted wire spelling | Enclosing protocols can demand canonical input | Canonicalization alone does not require canonical received text; WVP must state its rule |

Inventory *all* signed and hashed objects: contracts, evidence bodies (including arbitrary source payloads), statements, decisions, manifests, claims, agreements, receipts, heads and relations. Business amounts represented as strings reduce one mismatch; they do not establish that every protocol field and evidence body fits a JCS profile.

For a candidate profile, define which fields may be JSON numbers, their ranges, and how exact larger integers are represented. A restricted safe-integer profile is a candidate, not a property JCS imposes on every application. Refuse incompatible values before any lossy numeric conversion. Do not silently convert legacy numbers into strings.

Produce a machine-readable matrix of identical bytes, changed bytes and refused inputs. Distinguish payload schema changes from canonicalization changes.

### 3. DSSE compatibility study

Compare the current signing input `verified:<purpose>:<version>\n || canonical(payload)` against DSSE's PAE over payload type and exact serialized payload.

Specify candidates for:

- distinct, versioned payload types for evidence, claims, decisions and registry objects; types are local identifiers, never instructions to fetch a schema;
- the boundary between payload identity and envelope identity: re-signing must not accidentally redefine a statement digest or chain predecessor;
- Ed25519 key encoding and strict verification behavior, continuing RFC 0002's work;
- external resolution of key IDs and authorization for actor, tenant, source and purpose;
- exact-byte verification followed by application use of those same verified bytes;
- parsing, duplicate-member, length and signature-count limits;
- application-specific thresholds and distinct-key counting, including how two-party agreements bind signing roles.

A DSSE key ID is an untrusted lookup hint, not proof of identity or authority. More signatures do not imply distinct authorized parties. Do not infer claimant/respondent roles from signature order.

Check DSSE's standard and URL-safe base64 acceptance requirements against WVP's existing canonical-base64 expectations. Do not label a deliberately narrower parser a generic conforming DSSE verifier without explaining the profile boundary. Changes to envelope encoding can leave payload signatures valid while changing envelope bytes; content commitments must specify exactly what they identify.

DSSE adds payload encoding/decoding and envelope overhead. Measure these costs rather than assuming it will be smaller or faster.

### 4. Evidence and deliverables

The study should provide:

1. A field-by-field dependency map for existing canonicalization and signing domains.
2. A pinned inventory of candidate libraries for Scala/JVM, Rust, JavaScript and Python, with maintenance, license, validation behavior and integration cost. Do not assume suitable support exists in every language.
3. An isolated comparison harness with deterministic test keys and synthetic fixtures. Keep experimental cases outside published normative vector directories; label them non-normative.
4. Cross-implementation results, including exact bytes, digests, verification outcomes and failure categories.
5. Representative measurements of envelope size and encode/sign/verify cost, reporting environment and payload sizes.
6. Separate recommendations: adopt in a future version, defer, or retain the existing format, with concrete reasons and estimated migration effort.

The study may recommend retaining either current component. Familiarity or popularity alone is insufficient; reduced implementation burden and preserved assurance must be demonstrated.

## Outcomes that change

None in this PR. Existing identifiers, bytes, digests, signatures, refusal ordering and published expectations remain unchanged.

Any subsequent adoption that changes a defined outcome needs an explicit new version under RFC 0001. This RFC deliberately allocates no future identifier. It neither amends nor blocks RFC 0002 or RFC 0003.

## Compatibility

Existing producers, verifiers and relying parties need do nothing.

A future migration proposal must enumerate affected dependencies and define explicit version dispatch. No fallback such as "try legacy, then JCS/DSSE" after verification fails. No reinterpretation of old objects, rewriting of ledger history or regeneration of old expected values.

If both versions coexist, keep separately identified commitments. Any linking assertion must state who authorizes the mapping and what it proves. Re-encoding and re-signing an old assertion does not retrospectively authenticate its time or improve source assurance.

## Vectors

Proposed *experimental* cases, not additions to normative conformance in this PR:

- DEL, C1, ASCII controls, supplementary characters, combining characters and lone surrogates;
- duplicate members at every nesting depth;
- integer precision boundaries, arbitrary-size integers, exponent notation, negative zero, and string-valued amounts;
- equivalent JSON values with differing received bytes;
- altered DSSE payload type or payload, unsupported types, malformed encodings and oversized envelopes;
- wrong key, unauthorized source/tenant/purpose, repeated signer keys and insufficient distinct authorized signatures;
- attempted cross-purpose and cross-version replay;
- unchanged legacy fixture outputs under the existing verifiers.

Publish a candidate's exact expected results before integrating it. Migration conformance vectors belong to the later versioned adoption proposal.

## Security considerations

An adversary may control payloads, envelope metadata, encoding, claimed purpose and signatures, and may replay old valid material. A candidate must preserve purpose separation and make parsing and resource limits explicit.

JCS reduces serialization ambiguity within its defined input domain; it does not establish source truth. DSSE binds bytes and payload type to signatures; it does not authenticate observation time, prevent evidence omission, resolve revocation backdating, choose an agreed contract, or enforce a business action.

Relying-party pins, signer authority, claim-bound completeness and independent source assurance remain separate WVP responsibilities. Retain RFC 0002 hardening and RFC 0003's semantic work regardless of this study's outcome. Protocol/security review is required before any adoption.

## Formal semantics

The Work Contract Language evaluation semantics do not change. Existing Lean results do not prove parsers, canonicalization, DSSE implementations or migration correctness.

The study supplies interoperability evidence through independent implementations and fixtures, not a proof for all inputs. A later adoption proposal must state its trusted libraries and any unproved representation bindings.

## Alternatives

- **Keep both current formats:** avoids migration and new dependencies; retains custom implementation and review burden.
- **Adopt JCS only:** may reduce canonicalizer maintenance while leaving existing envelopes.
- **Adopt DSSE only:** can standardize signing while preserving legacy payload bytes and digests in an explicitly versioned envelope.
- **Use JWS or COSE instead:** relevant envelope alternatives if DSSE's library support or transport costs are unsuitable. Do not expand this bounded study into a general framework comparison without a concrete blocker.
- **Replace WVP with Solidity:** changes execution infrastructure but does not define evidence admission, unknown/completeness semantics or relying-party expectations.

## Open questions

- Which real objects fail the proposed JCS input profile?
- Which maintained libraries reproduce the required behavior in each implementation language?
- Does DSSE meaningfully reduce custom code after trust and schema validation remain?
- Should stable identities commit to payloads, envelopes, or both for each object family?
- Which future version would carry adoption, if justified?
- Is migration worth its cost before two external producers need it?

## Decision

Pending maintainers' review. No adoption decision has been made.

## Implementation

None. This PR introduces a study proposal and updates the RFC index only.

## References

- [RFC 8785: JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785.html), especially sections 3.1–3.2 and Appendix D (Informational RFC, not Standards Track).
- [DSSE protocol](https://github.com/secure-systems-lab/dsse/blob/master/protocol.md).
- [DSSE envelope](https://github.com/secure-systems-lab/dsse/blob/master/envelope.md).

The study must pin upstream revisions and library versions for reproducible results.

# Canonical JSON: verified-json-v1

|                      |                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------- |
| Identifier           | `verified-json-v1`                                                                    |
| Version              | 1                                                                                     |
| Status               | Draft                                                                                 |
| Depends on           | Nothing                                                                               |
| Normative references | RFC 8259 (JSON); RFC 3629 (UTF-8)                                                     |
| Conformance          | [`test-vectors/canonical-hash-v1.json`](../../../test-vectors/canonical-hash-v1.json) |

`verified-json-v1` is the one byte form of a JSON value that every digest and every signature in the protocol family is computed over. Two implementations that hold the same value produce the same bytes, and a text that is not the canonical encoding of its own value is not canonical.

It is **not** RFC 8785 (JCS). The two agree on the order of keys, on UTF-8 and on the absence of whitespace. They differ on numbers and on which characters are escaped.

This document holds the rules that were stated, until now, in the description of the shared vectors. They are moved here unchanged, so that the encoding has a specification of its own. Nothing about the encoding changes with the move.

## 1. Rules

- Objects sort keys recursively by UTF-16 code-unit order (JVM string order).
- Arrays retain order and nulls remain present.
- Numbers must be mathematically integral and serialize in plain decimal, without leading zeroes or a negative zero. No floating-point rounding is allowed.
- Strings contain Unicode scalar values; unpaired surrogates in values or keys are rejected. No Unicode normalization occurs.
- Encoding is UTF-8, with no BOM or insignificant whitespace. JSON escaping uses short escapes for backspace, tab, newline, form feed and carriage return; all remaining characters in U+0000–U+001F and U+007F–U+009F use lowercase `\u00xx`. This applies to both keys and values; U+00A0 stays unescaped. Quotes and backslashes escape, ordinary slashes do not.
- Duplicate keys are outside the object model; these fixtures do not define duplicate-key parsing behavior.

## 2. What this version leaves open

These are stated so that an implementer does not have to discover them. Each is a question for the specification, tracked in the published repository, and none is decided here.

- **Duplicate keys.** The last rule puts them outside the object model and defines no behaviour for a text that has them.
- **The size of an integer.** The rules allow an integer of any size. Protocols that carry integers bound them where they need to.

## 3. Conformance

`test-vectors/canonical-hash-v1.json` holds valid cases, each with raw input JSON text, the expected canonical UTF-8 text and its SHA-256 digest, and invalid cases that must fail parsing or canonicalization. An implementation conforms when it reproduces the canonical bytes and the digest of every valid case and refuses every invalid case.

Agreement on these cases is evidence of interoperability, not a proof for every possible value. Changing established canonical bytes is a new version of this encoding, never a change to these expectations.

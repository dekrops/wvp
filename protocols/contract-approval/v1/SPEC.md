# Contract approval v1

|                      |                                                                                                                       |
| -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Identifier           | `verified.contract-approval/1`                                                                                        |
| Version              | 1                                                                                                                     |
| Status               | Draft                                                                                                                 |
| Depends on           | [`verified-json-v1`](../../canonical-json/v1/SPEC.md)                                                                 |
| Normative references | W3C Web Authentication Level 2; RFC 4648 (base64url); RFC 5280 (SubjectPublicKeyInfo); FIPS 186-5; RFC 8032; RFC 8017 |
| Conformance          | [`test-vectors/contract-approval/v1`](../../../test-vectors/contract-approval/v1)                                     |

Status: draft specification with a reference implementation and vectors. The Playground's control plane makes such approvals; this document is what a relying party needs to check one offline.

A **contract approval** records that an approver approved the exact text of a Work Contract after being shown a specific view of it. The approver signs a **statement** with a passkey (a WebAuthn credential): a platform authenticator, a security key or a phone. The private key never leaves the authenticator, so whoever holds the approval and the passkey's public key can check it without trusting the service that recorded it.

## 1. What an approval establishes

- Whoever approved held the passkey's authenticator at that moment, and the authenticator saw the user present.
- The approval is for exactly one contract (its digest) and one snapshot of what the approver was shown (its digest); changing either breaks the signature.
- **Not established:** who the person is. That a passkey belongs to an approver is the relying party's knowledge, from how the passkey was registered. **Not established:** what the person saw. Authenticators do not display what they sign; the snapshot is what the service says it showed. **Not established:** that the passkey is hardware-backed (no attestation is checked).

## 2. The approval

An approval is a JSON object with these members. Others are ignored.

| Member      | Value                                                                                    |
| ----------- | ---------------------------------------------------------------------------------------- |
| `statement` | The statement (section 3).                                                               |
| `assertion` | The WebAuthn assertion over the statement (section 5).                                   |
| `key`       | The passkey: `credentialId` (string), `publicKey` (string), `algorithm` (integer, COSE). |
| `shown`     | The snapshot: what the approver was shown (section 4).                                   |
| `rpId`      | The relying party the service used. Informative: a checker uses its own (section 6).     |

`publicKey` is the passkey's SubjectPublicKeyInfo (RFC 5280), DER, in base64url. `algorithm` is `-7` (ES256), `-8` (EdDSA with Ed25519) or `-257` (RS256).

## 3. The statement

A JSON object with exactly these eight members, each a string:

```json
{
  "type": "verified.contract-approval/1",
  "tenant": "tenant-1",
  "repository": "example/repository",
  "contract": "sha-256:<64 hex>",
  "shown": "sha-256:<64 hex>",
  "approver": "approver-1",
  "issuedAt": "2026-10-26T12:00:00Z",
  "nonce": "<issued by the service>"
}
```

`contract` is the digest of the approved contract's canonical text ([Work Contract Language 1](../../work-contract/v1/SPEC.md)). `shown` is the digest of the snapshot. `issuedAt` and `nonce` are the service's; this version does not check them offline.

## 4. The snapshot

The snapshot is a JSON object with a string member `contract`, equal to the statement's `contract`, and any other members (the view as the approver saw it). Its digest is

```text
shown = "sha-256:" ‖ hex( SHA-256( verified-json-v1(snapshot) ) )
```

in lowercase hex. A snapshot without a canonical form (a number that is not an integer, an unpaired surrogate) is malformed.

## 5. The challenge and the assertion

```text
challenge = SHA-256( verified-json-v1(statement) )
```

The approver's browser asks the authenticator for an assertion (`navigator.credentials.get`) with this 32-byte challenge. The assertion's four members, each base64url (RFC 4648, section 5; padding optional), are `credentialId`, `authenticatorData`, `clientDataJSON` and `signature`, as the browser returned them. The authenticator signs

```text
authenticatorData ‖ SHA-256(clientDataJSON)
```

- ES256: ECDSA over P-256 with SHA-256 (FIPS 186-5); the signature is DER-encoded.
- EdDSA: Ed25519 (RFC 8032); the signature is 64 bytes.
- RS256: RSASSA-PKCS1-v1_5 with SHA-256 (RFC 8017).

## 6. Checking an approval

The checker is given the approval, its relying party identifier `rpId` and the set of origins it accepts. It performs these steps in order and stops at the first that fails, reporting that step's code.

| Step | Check                                                                                                                                                                                                                                                                                                                                                            | Code                    |
| ---- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| 1    | `statement`, `assertion`, `key` and `shown` are present. The statement has exactly the eight members of section 3, each a string of Unicode scalar values (so that it has a canonical form), and `type` is `verified.contract-approval/1`. The assertion's four members and the key's `credentialId` and `publicKey` are strings, and `algorithm` is an integer. | `MALFORMED`             |
| 2    | The snapshot has a canonical form.                                                                                                                                                                                                                                                                                                                               | `MALFORMED`             |
| 3    | The snapshot's digest (section 4) equals the statement's `shown`.                                                                                                                                                                                                                                                                                                | `SNAPSHOT_MISMATCH`     |
| 4    | The snapshot's `contract` is a string equal to the statement's `contract`.                                                                                                                                                                                                                                                                                       | `SNAPSHOT_CONTRACT`     |
| 5    | The assertion's `credentialId` equals the key's.                                                                                                                                                                                                                                                                                                                 | `OTHER_PASSKEY`         |
| 6    | `authenticatorData`, `clientDataJSON`, `signature` and `publicKey` decode as base64url.                                                                                                                                                                                                                                                                          | `MALFORMED`             |
| 7    | `clientDataJSON` is UTF-8 JSON.                                                                                                                                                                                                                                                                                                                                  | `MALFORMED`             |
| 8    | Its `type` is `webauthn.get`.                                                                                                                                                                                                                                                                                                                                    | `CEREMONY`              |
| 9    | Its `challenge` is the base64url encoding, without padding, of the challenge of section 5.                                                                                                                                                                                                                                                                       | `CHALLENGE`             |
| 10   | Its `origin` is one of the accepted origins, compared as strings.                                                                                                                                                                                                                                                                                                | `ORIGIN`                |
| 11   | `authenticatorData` is at least 37 bytes.                                                                                                                                                                                                                                                                                                                        | `MALFORMED`             |
| 12   | Its first 32 bytes are SHA-256 of `rpId` (UTF-8).                                                                                                                                                                                                                                                                                                                | `RELYING_PARTY`         |
| 13   | Its flags byte (byte 32) has the user-present bit (`0x01`) set.                                                                                                                                                                                                                                                                                                  | `USER_NOT_PRESENT`      |
| 14   | The key's `algorithm` is `-7`, `-8` or `-257`.                                                                                                                                                                                                                                                                                                                   | `UNSUPPORTED_ALGORITHM` |
| 15   | The public key is a key of that algorithm, and `signature` is its signature over `authenticatorData ‖ SHA-256(clientDataJSON)` (section 5).                                                                                                                                                                                                                      | `SIGNATURE`             |

If every step passes, the approval is valid, and the checker reports the statement.

Not checked in this version: the user-verified flag, the signature counter, attestation, `crossOrigin`, `topOrigin` and other members of the client data, and `issuedAt`. Whether the passkey is the approver's is for the relying party to know.

## 7. Conformance

`test-vectors/contract-approval/v1/vectors.json` holds `cases`, each with a `name`, the relying party's `rpId` and accepted `origins`, an `approval`, and the `expected` outcome: `{ "valid": true, "statement": …, "challenge": … }` with the statement and the base64url challenge, or `{ "valid": false, "refusal": <code> }`. Each invalid case fails exactly one step. An implementation conforms when it reaches the expected outcome for every case. The keys and data are synthetic, and the vectors are never regenerated: ECDSA signatures are randomized, so a second generation would give other bytes.

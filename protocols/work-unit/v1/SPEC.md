# Work-unit identity v1

Status: draft specification with a reference implementation and vectors. **Nothing in the product uses it yet**, and nothing here changes how claims are recorded or settled.

A **work unit** is what may be billed once. This document defines how a claim is mapped to the unit it is about, a **nullifier** that lets two claims about the same unit be recognized without disclosing which unit it is, and what a stateful registry must do to make a unit billable at most once. The design follows one reference submission's nullifier construction, and the commercial trial's `BillableWorkKey`, which it generalizes.

## 1. Three separate questions

| Question                                                | What answers it                                       | In this document    |
| ------------------------------------------------------- | ----------------------------------------------------- | ------------------- |
| Is this proof, package or record valid?                 | Verification, offline, statelessly                    | No                  |
| Are these two claims about the same unit of work?       | Equality of nullifiers                                | Sections 2 to 4     |
| Has this unit already been accepted, billed or settled? | **A stateful registry**, with atomic first-write-wins | Section 6, proposed |

No offline check, proof or digest can answer the third. A valid package for a unit that was already billed is still a valid package.

## 2. Which unit a claim is about: the scope

An invoice is not a work unit. One invoice can legitimately be captured, approved, posted and paid, and each can be separate billable work. What counts as one unit is therefore declared by the parties, per agreement, as a **scope**:

```json
{
  "scope": "invoice-processing",
  "operation": "process",
  "identity": ["invoice"]
}
```

- `scope` names the agreement's line of work and **stays the same across versions of the contract**. A unit billed under version 1.0.0 is the same unit under 1.1.0. A new contract version is therefore not a way to bill the same work again.
- `operation` separates different work on the same objects. Processing and posting one invoice have different operations, so they are different units.
- `identity` names the claim inputs ([Work Contract Language 1](../../work-contract/v1/SPEC.md), section 2) that identify one unit, in order. If the same number can occur in two source systems, the scope must include the system among them.

The scope is approved with the contract but is **not part of the contract language**. The language and its digest are unchanged; the scope is a separate, versioned object whose digest an approval covers. Two contracts that share a scope share units on purpose; contracts that should not share one must not share the name.

Values are compared exactly: no case folding, no trimming, no removal of leading zeros. `INV-01001` and `INV-1001` are different units. Normalization is decided by whoever defines the inputs, before they become claim inputs.

## 3. The identity

```text
identity = [ "work-unit-1", tenant, scope, operation, [ value_1, …, value_n ] ]
```

It is a JSON array with exactly one value per input the scope names. Its bytes are its `verified-json-v1` canonical form. The tenant is part of the identity: the same invoice number for two tenants is two units.

## 4. The nullifier

```text
nullifier = HMAC-SHA-256( k_t, "verified:work-unit-nullifier:v1\n" ‖ canonical(identity) )
```

`k_t` is a 32-byte secret key of tenant `t`. The result is reported as `{ "algorithm": "hmac-sha-256", "hex": … }`.

Each key is pinned by a commitment:

```text
commitment(k) = SHA-256( "verified:work-unit-key:v1\n" ‖ k )
```

| Property                                        | How                                                                                                                                                           |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One unit, one nullifier                         | The identity is a deterministic function of tenant, scope, operation and values; HMAC is deterministic                                                        |
| Tenants do not share a namespace                | The tenant is inside the identity, and each tenant has its own key                                                                                            |
| No dictionary attack on low-entropy identifiers | Without `k_t`, an attacker cannot compute the nullifier of a guessed invoice number. **Whoever holds `k_t` can.**                                             |
| The key cannot be switched silently             | Its commitment is recorded (section 5). A nullifier names the key it was derived under                                                                        |
| Correct derivation can be checked               | By anyone holding `k_t`, by recomputation. **Not by others:** a third party would need a proof of correct derivation, which is not specified here (section 8) |

### From whom the nullifier keeps the identity private

Verified holds `k_t` and, in protocol v0.2, receives claims and evidence in plaintext. **The nullifier is not privacy from Verified.** It keeps the unit's identity from parties who see nullifiers but not plaintext: an auditor shown a list of records, the other party's tooling, another tenant, anyone a record is exported to. If the tenant is given `k_t` it can check every nullifier of its own units. If `k_t` leaks, every nullifier of that tenant becomes open to a dictionary attack, and the key must be rotated.

## 5. Keys: rotation and compromise

- A tenant's keys form an ordered list, each with an identifier and a commitment, recorded in the tenant's ledger when the key is introduced. A key's commitment never changes. A key is never reused after rotation.
- A nullifier is always stored with the identifier of the key that produced it.
- **Rotation does not break duplicate detection**, because the registry checks a new unit against the nullifiers of every key the tenant has ever had. Verified holds those keys and the plaintext identity, so it can compute them. A vector shows the same unit under two keys having different nullifiers: this is why one key alone is not enough.
- **Compromise:** rotate, record the time from which the old key is considered exposed, and treat nullifiers published under it as no longer private. Duplicate detection is unaffected. Privacy of past nullifiers cannot be restored.
- Historical verification never needs a key: it compares recorded nullifiers, it does not recompute them.

## 6. The registry (proposed; not implemented)

Global uniqueness needs state. The proposal is to use the **tenant's existing ledger**, not a new service, a second ledger or a lock service: appends are already serialized per tenant, which is the atomicity a first-write-wins rule needs.

Proposed facts, in a future ledger schema version:

| Fact                                                                    | Rule at replay                                                                                            |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `WorkUnitKeyIntroduced(keyId, commitment, from)`                        | New key identifier and commitment, in order                                                               |
| `WorkUnitRegistered(nullifier, keyId, scopeDigest, claimId, recordRef)` | The nullifier is not held by **another** claim, under any key. The same claim again is accepted (retries) |
| `WorkUnitReleased(nullifier, claimId, reason, by)`                      | Only for a held unit, by an explicit, recorded decision (reversal, upheld dispute)                        |

The open questions it answers:

| Situation                                     | Proposed behaviour                                                                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Retry of the same claim                       | The same claim registering the same nullifier again is accepted, so recording is idempotent                                           |
| Two claims concurrently                       | The second append sees the first and is refused (`DUPLICATE_WORK_UNIT`): appends are serialized per tenant                            |
| A claim whose verification is not `SUPPORTED` | **Does not register a unit.** A unit is held only by work that can be billed; a contradicted or undetermined claim leaves it free     |
| Reversal or upheld dispute                    | The unit is released by a recorded fact and can be registered again. Nothing is released implicitly                                   |
| Re-verification of historical evidence        | Uses the recorded nullifier; registers nothing                                                                                        |
| Two contract versions                         | Same scope, same unit: refused as a duplicate                                                                                         |
| Two contracts sharing a scope                 | Same unit, by the parties' declaration                                                                                                |
| Two operations on one invoice                 | Different units                                                                                                                       |
| The same number in two source systems         | Different units only if the scope names the system                                                                                    |
| Duplicates across tenants                     | **Not detected**, by design: identities and keys are per tenant. Billing one piece of work to two customers is outside this mechanism |

Until such a registry is built, **no settlement behaviour changes**. The commercial trial, which refused a second finalization with the same `BillableWorkKey`, has been removed (record); protocol v0.2 work records keep refusing a second record per claim and per package.

## 7. Relation to `BillableWorkKey`

The removed commercial trial identified billable work by `(tenantId, contractId, workType, sourceId, subjectId)`, in plaintext, inside the tenant's journal.

| `BillableWorkKey`       | Work-unit identity v1 | Difference                                                               |
| ----------------------- | --------------------- | ------------------------------------------------------------------------ |
| `tenantId`              | `tenant`              | Same                                                                     |
| `contractId`            | `scope`               | The scope survives a new contract version; a contract identifier may not |
| `workType`              | `operation`           | Same idea                                                                |
| `sourceId`, `subjectId` | `identity` values     | Declared per scope instead of fixed to two                               |
| plaintext               | keyed nullifier       | Can be shown to others without revealing the subject                     |

A rebuild of the commercial trial should use this identity instead of a plaintext key.

## 8. Not in this version

- **A proof of correct derivation.** Showing a third party that a nullifier was derived from the invoice inside a signed statement, without revealing either, would be one more check in the source-authenticated proof profile: HMAC over the identity, with the key's commitment as a public input. It is not specified here, and with Verified holding the key, it would prove Verified's honesty about derivation, not more.
- **The registry**, its ledger facts and their schema version.
- **Cross-tenant uniqueness.**
- **Normalization rules** for identifiers.

## 9. Conformance

`test-vectors/work-unit/v1/vectors.json`: test keys with their commitments, and cases of tenant, scope and values with the expected canonical identity and nullifier. The Scala reference (`verified.crypto.WorkUnit`) and an independent JavaScript implementation (`tooling/work-unit.mjs`) reproduce every case. The test keys are public and must never be used outside the vectors.

# Work relation v1

Status: draft specification with a Scala reference (`modules/work-relation`) and vectors (`test-vectors/work-relation/v1`). There is no second implementation yet, so nothing here has been checked by agreement between two. The platform's ledger issues `recorded` and `linked` (ADR 0042); nothing issues `groups`. The data in the vectors is synthetic.

One unit of work leaves several records: a package, a work record in a ledger, a registration at a claim registry. Each is verifiable alone. A **work relation** is a signed statement by which an authority says how records it knows are related, so that someone holding several of them can establish, offline, which belong together and who says so.

This specification defines the relation, how it is carried, and what a reader may conclude from a set of relations and records. It defines no new record, no new signature and no new trust format (ADR 0041).

## 1. What a relation is, and is not

A relation shows that **an authority said something, within its scope**. It does not show that the thing is true.

- A ledger's `recorded` shows that the ledger holds a record. It does not show that the record's decision is right, or that the ledger holds nothing else.
- Leaving a record out never makes a set of relations invalid. It makes relations to that record **stated**: read, and not checked.
- There is no single result for a set. Each relation has its own standing (section 6).

## 2. References

A record is named by a **reference**: a kind, and that kind's own digest.

```json
{ "kind": "work-record", "digest": { "algorithm": "sha-256", "hex": "…" } }
```

| Kind               | The record                                          | Its digest                                   |
| ------------------ | --------------------------------------------------- | -------------------------------------------- |
| `package`          | A WVP v0.2 package                                  | Its package commitment                       |
| `work-record`      | A work record (WVP v0.2, section 7)                 | SHA-256 of the record's canonical JSON       |
| `agreement`        | A claim registration agreement, with its signatures | Claim registration's digest of the agreement |
| `claim-commitment` | A claim registration claim, with its signature      | Claim registration's digest of the claim     |
| `receipt`          | A claim registration receipt, with its signature    | Claim registration's digest of the receipt   |

For the three claim registration kinds the digest is of the object that was signed, not of the object with its signatures, as that specification defines it.

Two references are the same only if both the kind and the digest are equal. A reference of one kind never names a record of another, whatever the bytes. Identifiers that are not digests (a claim ID, a registry's sequence number) appear in relations as **attributes**. An attribute never names a record, and a reader never joins records on an attribute alone.

A digest is SHA-256 with 64 lowercase hexadecimal digits. Later minor versions may add kinds.

## 3. Relations

A relation body is a JSON object with exactly two members: `protocol`, which is `verified-work-relation-v1`, and one member named after the relation.

### `recorded`

Said by a ledger: it holds this work record.

```json
{
  "protocol": "verified-work-relation-v1",
  "recorded": {
    "record": {
      "kind": "work-record",
      "digest": { "algorithm": "sha-256", "hex": "…" }
    },
    "claimId": { "value": "00000000-0000-4000-8000-000000000507" }
  }
}
```

It does not mean the record is true, that the claim was accepted, or that the ledger holds no other record of the claim.

### `linked`

Said by a ledger: it holds this registration for this work record.

| Member      | Value                                        |
| ----------- | -------------------------------------------- |
| `record`    | reference, kind `work-record`                |
| `agreement` | reference, kind `agreement`                  |
| `claim`     | reference, kind `claim-commitment`           |
| `receipt`   | reference, kind `receipt`                    |
| `claimId`   | the claim ID                                 |
| `registry`  | the registry's name, as the receipt has it   |
| `sequence`  | the receipt's position in the registry's log |

It does not state the claim's state at the registry. That is in the registry's log, and changes.

### `groups`

Said by an application: these records belong to one group, as the application defines it.

| Member    | Value                                                                                            |
| --------- | ------------------------------------------------------------------------------------------------ |
| `group`   | the group's name, a non-empty string                                                             |
| `members` | one or more references of kind `package` or `work-record`, distinct, in the order of section 3.1 |

It does not mean the group is complete, or that the members agree with each other.

### 3.1 Order of members

Members are ordered by kind, then by the digest's hexadecimal text, both compared as byte strings. A body whose members are in another order, or repeat, is malformed. A group therefore has one encoding.

## 4. Carrier

A relation is carried by an **Evidence Statement v1** (`verified-evidence-statement-v1`). Nothing about that statement changes: its canonical form, its signing input, its trust registry and its checks are those of its own specification.

A statement carries a relation when:

| Statement member | Must be                                                               |
| ---------------- | --------------------------------------------------------------------- |
| `kind`           | `SignedAttestation`                                                   |
| `payload`        | the SHA-256 of the canonical relation body                            |
| `subject.system` | the statement's `source.system`                                       |
| `subject.kind`   | `work-relation`                                                       |
| `subject.key`    | the claim ID for `recorded` and `linked`; the group name for `groups` |

The statement's `observedAt` is when the authority says so. A relation body has no time of its own.

**The authority is the statement's source.** A reader accepts a relation only when the statement verifies under the reader's own trust registry, which authorizes each key for named sources. Who may speak as a ledger or as an application is therefore the reader's decision, made in its trust registry, and never read from the relation.

An authority that wants to show it has left nothing out issues its relations in a stream of their own (the statement's `chain`), and nothing else in that stream.

## 5. Reading

A reader is given:

- **relations**: signed statements, each with its body;
- **records**: texts, each with the kind it is offered as;
- an evidence **trust registry**.

It needs no network and no clock.

### 5.1 Records

Each record text is parsed as its kind, strictly as its own specification requires: it is the canonical encoding and has no member that specification does not define. Its digest is computed as in section 2. A text that does not parse is reported as `MALFORMED_RECORD` and is not held. A kind this version does not define is reported as `UNKNOWN_KIND`. Two held records of one kind with one digest are one record.

A package is held only as what its text commits to: its stated commitment is the SHA-256 of its manifest, and its `claim.json` has the digest the manifest names. Nothing else of the package is read here.

**Holding a record is not verifying it.** This specification resolves references and compares what records state. Whether a package verifies, whether a registration verifies and under which keys, is decided by those specifications, and a reader reports those results beside the relations.

### 5.2 One relation

Checks run in this order and stop at the first failure.

1. The statement verifies, as Evidence Statement v1 requires. A failure keeps its code.
2. The body's SHA-256 is the statement's `payload`: `PAYLOAD_MISMATCH`.
3. The body is read, in this order:
   - it is an object with a string `protocol`: `MALFORMED`;
   - `protocol` is this one: `UNSUPPORTED_PROTOCOL`;
   - it has exactly one other member: `MALFORMED`;
   - that member names a relation of section 3: `UNKNOWN_RELATION`;
   - its value has exactly that relation's members, each reference has a kind the relation allows and a well-formed digest, `registry` and `group` are not empty, `sequence` is not negative, and members are in the order of section 3.1: `MALFORMED`.
4. The statement carries it as in section 4: `CARRIER_MISMATCH`.

A relation that fails any of these is **refused**, with that code.

Then each reference is **resolved**: it is held, or it is absent. Then what the relation states is compared with what the held records state. The comparisons, in order, each only when the records it needs are held:

| Relation   | Comparison                                                      | Code                 |
| ---------- | --------------------------------------------------------------- | -------------------- |
| `recorded` | the work record's `claimId` is the relation's                   | `CLAIM_MISMATCH`     |
| `linked`   | the work record's `claimId` is the relation's                   | `CLAIM_MISMATCH`     |
| `linked`   | the claim commitment's `id` is the relation's `claimId`         | `CLAIM_MISMATCH`     |
| `linked`   | the claim commitment names the agreement by its digest          | `AGREEMENT_MISMATCH` |
| `linked`   | the agreement's `tenant` is the statement's `tenant`            | `TENANT_MISMATCH`    |
| `linked`   | the agreement's contract digest is the work record's `contract` | `CONTRACT_MISMATCH`  |
| `linked`   | the receipt names the claim commitment by its digest            | `RECEIPT_MISMATCH`   |
| `linked`   | the receipt's `registry` and `sequence` are the relation's      | `RECEIPT_MISMATCH`   |
| `linked`   | the agreement's `registry` is the receipt's                     | `REGISTRY_MISMATCH`  |

`groups` has no comparison: membership is the application's to define.

### 5.3 Standing

| Standing       | Meaning                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| `REFUSED`      | Not a relation the reader accepts. Carries the code                                                    |
| `CONTRADICTED` | Authentic, and a held record states otherwise. Carries the first code                                  |
| `CHECKED`      | Authentic, every reference is held, and every comparison agrees                                        |
| `STATED`       | Authentic, nothing held contradicts it, and at least one reference is absent. Carries those references |

`CHECKED` means the authority's statement is consistent with the records in hand. It is not a verification result.

A record that was altered has another digest, so it is another record: the reference to the original is absent and the relation is `STATED`. Nothing here can tell an altered record from a missing one, and nothing here needs to.

## 6. One claim, in a package and at a registry

A package's claim and a registered claim are **the same claim** when the claim commitment's `id` is the package claim's `id` and all four of these hold, checked in this order:

| Check                                                                          | Code                |
| ------------------------------------------------------------------------------ | ------------------- |
| the agreement's `tenant` is the package claim's `tenant`                       | `TENANT_MISMATCH`   |
| the agreement's contract digest is the package claim's `contract`              | `CONTRACT_MISMATCH` |
| the agreement's `claimant` is the package claim's `claimant`                   | `CLAIMANT_MISMATCH` |
| the claim commitment's `inputs` is the SHA-256 of the package claim's `inputs` | `INPUTS_MISMATCH`   |

The agreement is the one the claim commitment names by digest.

This is a **derived** relation: no one signs it, and anyone holding the three records computes it. Equal claim IDs alone establish nothing. For every held package and held claim commitment with one claim ID, where the agreement the commitment names is held too, a reader reports `SAME_CLAIM` or the first code. Where that agreement is not held, it reports nothing.

## 7. Completeness

A set of relations says nothing about relations that are not in it, unless their authority chained them.

For each stream (one tenant, issuer and stream name) the reader computes continuity as Evidence Statement v1 defines it, from chain positions only, and reports one of:

| Completeness    | Meaning                                                                                            |
| --------------- | -------------------------------------------------------------------------------------------------- |
| `UNINTERRUPTED` | Every position from the stream's first to the last one presented is present. Carries that position |
| `UNKNOWN`       | Anything else: a position is missing, or the stream's first statement was not presented            |

Relations without a chain position belong to no stream, and their completeness is `UNKNOWN`. A stream whose presented statements contradict each other is refused with the chain's own code.

`UNINTERRUPTED` says nothing about what follows the last position: a stream cut short is indistinguishable from one that stopped. Only the authority's own later statement, or an anchor the reader holds from elsewhere, can show more. For a registry the equivalent is its signed head, which claim registration defines and this specification does not repeat.

## 8. What this version does not do

- **It carries no registry state.** Closures, dispute records and heads are checked as claim registration defines. A later version may name them as kinds.
- **It does not repeat a record's own references.** Whether a work record is about a package is WVP v0.2's check, and whether a receipt belongs to a claim under an agreement is claim registration's.
- **It defines no container.** How relations and records travel together is not specified.
- **It defines no relation for acceptance, settlement or finality.** Those are records with authors. When such a record exists, a relation can name it.
- **It authenticates no time.** `observedAt` is what the authority says, as for any statement.

## 9. Conformance

`test-vectors/work-relation/v1/vectors.json` holds, for each case, the relations, the records and the trust registry, and the expected reading: each record's digest or `MALFORMED_RECORD`, each relation's standing with its code or absent references, each derived relation, and each stream's completeness. An implementation conforms when it computes the same reading for every case.

# Purchase-order authorization: attested, not recomputed

A worked example in Work Contract Language 1 as it is. Nothing was added to the language for it, and nothing here is normative.

It shows the first of the two ways a contract can rely on an authorization engine such as [Cedar](https://www.cedarpolicy.com/):

1. **Attested.** The system that enforced the action says what its engine decided, in a record of its own. This example.
2. **Recomputed.** The verifier evaluates the historical policies itself. Not part of the protocol; it would become so only by [RFC](https://github.com/dekrops/wvp/blob/main/rfcs/0001-standards-process.md).

The two are different facts. A decision record establishes that an accepted enforcement point **said** Allow or Deny. It does not establish what the policy set yields, and a contract chooses which of the two it needs by the sources it accepts.

## What is assumed before evaluation

A contract is evaluated over an environment of facts, each with a `source`. **Nothing in this example verifies a signature.** That a fact marked `enforcement-point` really comes from that enforcement point, unaltered, is established before evaluation, by verifying the evidence statement that carried it against a trust registry. The cases here are plain environments: they assume that step has happened and prove nothing about it.

## The decision record

A record of kind `authorizationDecision`, from the enforcement point:

| Field             | Type           | Meaning                                                                                   |
| ----------------- | -------------- | ----------------------------------------------------------------------------------------- |
| `id`              | text, key      | The enforcement point's identifier of the decision                                        |
| `request`         | text           | The request that was authorized: here the identifier of the approval, as the ERP records it |
| `principal`       | text           | Who asked, as the approval names them                                                     |
| `action`          | text           | The action, as an entity identifier of the engine                                         |
| `resource`        | text           | What was acted on, as the contract's input names it                                       |
| `policySet`       | text           | Digest of the policy set that was evaluated                                               |
| `schema`          | text           | Digest of the schema the policies and entities were validated against                     |
| `engine`          | text           | The engine's implementation and version                                                   |
| `languageVersion` | text           | The policy language version                                                               |
| `at`              | time           | When the decision was made                                                                |
| `engineDecision`  | text           | What the engine returned, `Allow` or `Deny`, whatever else happened                       |
| `errors`          | int            | How many policies failed to evaluate                                                      |
| `permitted`       | bool, optional | `true` or `false` when the evaluation was clean. **Absent when `errors` is not zero**     |

`permitted` is the field a contract reads. An engine that reports an evaluation error has skipped a policy, and the skipped policy may have been the one that decides. So an errored evaluation carries what the engine returned and no decision. By the language's existing rule, a comparison with an absent optional field is `UNKNOWN`.

The contract does not rely on the enforcement point getting that omission right. See the rules below.

The record carries digests and a count. The policies, the request context and the engine's diagnostics stay with the enforcement point, named by the digests.

## Two contracts, one evidence

[`attested/draft.json`](attested/draft.json) and [`recomputed/draft.json`](recomputed/draft.json) are the purchase-order approval contract with one requirement, `APPROVAL_AUTHORIZED`, in place of the directory lookup. Every approval of the order has a decision that:

- **belongs to that approval**: its `request` is the approval's `id`, and it was made no later than the approval (`at` ≤ the approval's `at`);
- is for the approval's approver, the order and the approve action;
- was made under the policy set the contract names;
- has `permitted` true;
- **is clean and consistent**: if `permitted` is true, then `errors` is zero and `engineDecision` is `Allow`.

Principal, action and resource alone do not say which approval a decision authorized: the same person may approve the same order twice. The `request` identifier does. It is a convention between the ERP and the enforcement point, stated by both and compared here. The language has no durations, so "made shortly before" cannot be required, only "not after".

The last rule is written as an implication on purpose. A record with errors and no `permitted` stays `UNKNOWN`; a record that claims `permitted` despite errors, or despite a Deny, is `FALSE`.

They differ in one line: the source accepted for `authorizationDecision`. The first accepts `enforcement-point`. The second accepts only `authorization-recomputation`.

The same eight environments are evaluated under both:

| Case                         | Enforcement point's record                             | Attested       | Recomputed     |
| ---------------------------- | ------------------------------------------------------ | -------------- | -------------- |
| `1-allowed`                  | Clean Allow for this approval                          | `SUPPORTED`    | `UNDETERMINED` |
| `2-denied`                   | Clean Deny                                             | `CONTRADICTED` | `UNDETERMINED` |
| `3-allowed-with-errors`      | Allow, one policy errored, `permitted` absent          | `UNDETERMINED` | `UNDETERMINED` |
| `4-other-policy-set`         | Clean Allow under a policy set not named here          | `CONTRADICTED` | `UNDETERMINED` |
| `5-permitted-despite-errors` | Inconsistent: `permitted` true, one policy errored     | `CONTRADICTED` | `UNDETERMINED` |
| `6-permitted-despite-deny`   | Inconsistent: `permitted` true, the engine said Deny   | `CONTRADICTED` | `UNDETERMINED` |
| `7-other-request`            | Clean Allow, same principal and order, another request | `CONTRADICTED` | `UNDETERMINED` |
| `8-decided-after-approval`   | Clean Allow for this request, made after the approval  | `CONTRADICTED` | `UNDETERMINED` |

Only the first is `SUPPORTED`, and the test asserts exactly that: no errored, inconsistent, misdirected or late record supports the contract.

Under the second contract the enforcement point's record is ignored, as any record from a source a contract does not accept, and no accepted source has said anything. That is `UNDETERMINED`: never a rejection, and never an approval taken on the enforcer's word.

No case shows the second contract `SUPPORTED`, because no record from a recomputing verifier exists in the protocol today.

## What `CONTRADICTED` means here

In every case but `2-denied`, `CONTRADICTED` says one thing: **the enforcement point declares its decisions complete, and none of them is a clean permission for this approval under the named policy set.** Without that declaration each of these cases is `UNDETERMINED`.

In particular `4-other-policy-set` does **not** establish that the engine would have denied the request under the required policy set. Nobody evaluated that. It establishes that the enforcement point has no record of having permitted it under that set. Whether the policies would permit it is the question of recomputation, which this example does not answer.

## Limits

- **Three fields are carried and not checked.** The contract reads `policySet`. It does not read `schema`, `engine` or `languageVersion`, so a decision made with another schema, another engine or another language version is accepted like any other. Binding them needs three more policy parameters and three more comparisons, and these negative cases, each expected `CONTRADICTED` under a complete listing and `UNDETERMINED` otherwise: a clean Allow under another schema digest; from another engine version; under another language version. They are proposed, not written: which engine versions a contract may accept as equivalent is a question for the RFC.
- **`errors` is the enforcement point's count.** The contract refuses a record that contradicts itself. It cannot detect an enforcement point that reports zero errors when there were some. That is a false statement by an accepted source, which no verifier detects.
- **The `request` identifier is as good as the two systems' agreement on it.** If the ERP and the enforcement point do not share one, a decision cannot be bound to an approval by this contract.
- The principal and the resource are compared as text with the approval's approver and the order number. Mapping them to an engine's entity identifiers is the enforcement point's business.
- All data is synthetic. The digests are not digests of real policies.

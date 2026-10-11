# A model of RFC 0003's checks

`WvpV03.lean` models the checks that [RFC 0003](../../0003-wvp-0.3.md) adds to package verification, and proves four properties of the model. It accompanies a proposal: it is not a definition any specification refers to, and it is not part of [`formal/lean`](../../../formal/lean/README.md).

```sh
bash rfcs/0003/formal/check.sh
```

The same Lean toolchain as `formal/lean`, no dependencies, warnings as errors, no `sorry`, `admit`, custom `axiom` or `native_decide`.

## What is modelled

Steps 9, 11, 12 and 14 of the RFC's algorithm, and `standing`. A package is its tenant, its contract digest, its claim, the registry's entry for the key that signed the claim, its admitted records and its admitted completeness statements.

## What is assumed

| Assumed                                                | In the model                                                            |
| ------------------------------------------------------ | ----------------------------------------------------------------------- |
| Signature checking                                     | `claimSigned` is its outcome. Records and listings are already admitted |
| Hashing                                                | A digest is a number, and equal digests mean equal things               |
| The digest of a listed set                             | The list itself                                                         |
| The contract language                                  | Any function `eval` of the records and the closed kinds                 |
| Key validity, times, canonical encoding, the container | Not modelled                                                            |

## What is proved

| Theorem                     | Statement                                                                                                                                                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `claim_binding`             | An accepted package's claim was signed under a key the registry holds for the package's tenant, as the claimant, in the claimant role. It names the package's contract, and the records are exactly those it names |
| `closed_kind_is_as_listed`  | In an accepted package, a closed kind has, for every source the contract accepts for it, a completeness statement for the claim's inputs whose set is exactly the package's records of that kind from that source  |
| `same_listing_same_records` | Two accepted packages carrying one completeness statement hold the same records of its kind from its source. None can be left out of one, and none added                                                           |
| `established_needs_pins`    | A result is established only if the relying party gave the tenant and the contract, and they are the package's                                                                                                     |
| `no_pins_never_established` | Without both, no package is established, whatever it contains                                                                                                                                                      |
| `added_checks_only_refuse`  | Whatever the procedure accepts, the procedure without the claim signature and the completeness check accepts too, with the same decision                                                                           |

## What this does not show

These are properties of definitions written for the purpose. They show that the design, as modelled, has the invariants the RFC claims, and they would fail to compile if a change to the model broke one. They say nothing about an implementation, about the encodings, or about a source's honesty: `closed_kind_is_as_listed` is about what a source signed, not about what it holds. The first and the last theorem follow almost directly from the definitions; they are stated so that the invariant has a name and a check.

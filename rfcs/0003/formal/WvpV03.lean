/-!
A model of the checks RFC 0003 adds to package verification, and four properties of it.

Digests, keys, tenants, sources and kinds are numbers. Hashing and signature checking are
assumed, not modelled: a digest is the thing it is a digest of, and `claimSigned` is the outcome
of checking the claim's signature. The contract language is a parameter (`eval`), so nothing here
depends on how a contract is evaluated.

What is proved is about these definitions. It is not a proof about any implementation.
-/

namespace WvpV03

/-- A key as the relying party's registry describes it. -/
structure Key where
  tenant : Nat
  /-- The registry's `issuer`: whose key it is. -/
  holder : Nat
  /-- Whether its sources include the role `wvp-claim`. -/
  claimRole : Bool
  deriving DecidableEq, Repr

/-- An admitted `record` statement. -/
structure Record where
  digest : Nat
  kind : Nat
  source : Nat
  deriving DecidableEq, Repr

/-- An admitted completeness statement. `records` stands for the digest of the listed set. -/
structure Listing where
  kind : Nat
  source : Nat
  inputs : Nat
  records : List Nat
  deriving DecidableEq, Repr

structure Claim where
  tenant : Nat
  claimant : Nat
  contract : Nat
  inputs : Nat
  evidence : List Nat
  deriving DecidableEq, Repr

structure Package where
  tenant : Nat
  /-- The digest of `contract.json`. -/
  contract : Nat
  claim : Claim
  /-- The registry's entry for the key that signed the claim, if it holds one. -/
  claimKey : Option Key
  /-- The outcome of checking the claim's signature under that key. -/
  claimSigned : Bool
  records : List Record
  listings : List Listing
  /-- The decision the package states. -/
  decision : Nat

/-- What the relying party pins. It is an argument of verification, never part of a package. -/
structure Expectations where
  tenant : Option Nat
  contract : Option Nat

/-- The sources a contract accepts for each kind. -/
abbrev Accepts := Nat → List Nat

/-- The digests of the records of one kind from one source, in the package's order. -/
def listed (p : Package) (kind source : Nat) : List Nat :=
  (p.records.filter fun r => r.kind == kind && r.source == source).map (·.digest)

/-- Step 9: the claim is signed by a key registered for this claimant, tenant and role. -/
def claimAuthentic (p : Package) : Bool :=
  p.claimSigned &&
    match p.claimKey with
    | some k => k.tenant == p.claim.tenant && k.holder == p.claim.claimant && k.claimRole
    | none => false

/-- Steps 11 and 13, as far as they bind the claim: tenant, contract and evidence. -/
def claimBound (p : Package) : Bool :=
  p.claim.tenant == p.tenant && p.claim.contract == p.contract &&
    p.records.map (·.digest) == p.claim.evidence

/-- Step 12, for one completeness statement. -/
def listingHolds (p : Package) (l : Listing) : Bool :=
  l.inputs == p.claim.inputs && listed p l.kind l.source == l.records

/-- Change 4: a kind is closed when every accepted source has a completeness statement. -/
def closed (accepts : Accepts) (p : Package) (kind : Nat) : Bool :=
  (accepts kind).all fun s => p.listings.any fun l => l.kind == kind && l.source == s

/-- Step 14. `eval` is the contract language: any function of the records and the closed kinds. -/
def decisionReproduced (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (p : Package) : Bool :=
  eval p.records (closed accepts p) == p.decision

/-- Verification under a registry: steps 9 to 14 of RFC 0003. -/
def accepted (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts) (p : Package) : Bool :=
  claimAuthentic p && claimBound p && p.listings.all (listingHolds p) &&
    decisionReproduced eval accepts p

/-- The same procedure without the two checks this version adds (steps 9 and 12). -/
def acceptedBefore (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (p : Package) : Bool :=
  claimBound p && decisionReproduced eval accepts p

inductive Standing where
  | refused
  | reproduced
  | established
  deriving DecidableEq, Repr

/-- Change 6: a result is established only under the relying party's tenant and contract. -/
def standing (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts) (e : Expectations)
    (p : Package) : Standing :=
  if accepted eval accepts p then
    if e.tenant == some p.tenant && e.contract == some p.contract then .established
    else .reproduced
  else .refused

/-- Claim binding. An accepted package's claim was signed under a key the registry holds for the
    package's tenant, as the claimant, in the claimant role; it names the package's contract; and
    the records are exactly those the claim names. -/
theorem claim_binding (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts) (p : Package)
    (h : accepted eval accepts p = true) :
    ∃ k, p.claimKey = some k ∧ k.tenant = p.tenant ∧ k.holder = p.claim.claimant ∧
      k.claimRole = true ∧ p.claim.contract = p.contract ∧
      p.records.map (·.digest) = p.claim.evidence := by
  simp only [accepted, claimAuthentic, claimBound, Bool.and_eq_true, beq_iff_eq] at h
  obtain ⟨⟨⟨⟨_, hkey⟩, ⟨htenant, hcontract⟩, hevidence⟩, _⟩, _⟩ := h
  cases hk : p.claimKey with
  | none => simp [hk] at hkey
  | some k =>
    simp only [hk, Bool.and_eq_true, beq_iff_eq] at hkey
    exact ⟨k, rfl, hkey.1.1.trans htenant, hkey.1.2, hkey.2, hcontract, hevidence⟩

/-- No omission under completeness. In an accepted package, a closed kind has, for every source
    the contract accepts for it, a completeness statement for this claim's inputs whose listed
    set is exactly the package's records of that kind from that source. -/
theorem closed_kind_is_as_listed (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (p : Package) (kind : Nat) (h : accepted eval accepts p = true)
    (hclosed : closed accepts p kind = true) :
    ∀ s ∈ accepts kind, ∃ l ∈ p.listings, l.kind = kind ∧ l.source = s ∧
      l.inputs = p.claim.inputs ∧ listed p kind s = l.records := by
  intro s hs
  simp only [accepted, Bool.and_eq_true, List.all_eq_true] at h
  simp only [closed, List.all_eq_true, List.any_eq_true, Bool.and_eq_true, beq_iff_eq] at hclosed
  obtain ⟨l, hl, hkind, hsource⟩ := hclosed s hs
  have hholds := h.1.2 l hl
  simp only [listingHolds, Bool.and_eq_true, beq_iff_eq] at hholds
  exact ⟨l, hl, hkind, hsource, hholds.1, by rw [← hkind, ← hsource]; exact hholds.2⟩

/-- So two accepted packages that carry the same completeness statement hold the same records
    of its kind from its source: none can be left out of one of them, and none added. -/
theorem same_listing_same_records (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (p q : Package) (l : Listing) (hp : accepted eval accepts p = true)
    (hq : accepted eval accepts q = true) (hlp : l ∈ p.listings) (hlq : l ∈ q.listings) :
    listed p l.kind l.source = listed q l.kind l.source := by
  simp only [accepted, Bool.and_eq_true, List.all_eq_true] at hp hq
  have h1 := hp.1.2 l hlp
  have h2 := hq.1.2 l hlq
  simp only [listingHolds, Bool.and_eq_true, beq_iff_eq] at h1 h2
  rw [h1.2, h2.2]

/-- Pins come from outside. A result is established only if the relying party gave the tenant
    and the contract, and they are the package's. -/
theorem established_needs_pins (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (e : Expectations) (p : Package) (h : standing eval accepts e p = .established) :
    accepted eval accepts p = true ∧ e.tenant = some p.tenant ∧ e.contract = some p.contract := by
  unfold standing at h
  split at h
  · rename_i hacc
    split at h
    · rename_i hpins
      simp only [Bool.and_eq_true, beq_iff_eq] at hpins
      exact ⟨hacc, hpins.1, hpins.2⟩
    · cases h
  · cases h

/-- Without both pins, no package is established, whatever it contains. -/
theorem no_pins_never_established (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (e : Expectations) (p : Package) (h : e.tenant = none ∨ e.contract = none) :
    standing eval accepts e p ≠ .established := by
  intro hs
  obtain ⟨_, ht, hc⟩ := established_needs_pins eval accepts e p hs
  cases h with
  | inl hn => rw [hn] at ht; cases ht
  | inr hn => rw [hn] at hc; cases hc

/-- The added checks only refuse. Whatever this procedure accepts, the procedure without the
    claim signature and the completeness check accepts too, with the same decision. -/
theorem added_checks_only_refuse (eval : List Record → (Nat → Bool) → Nat) (accepts : Accepts)
    (p : Package) (h : accepted eval accepts p = true) : acceptedBefore eval accepts p = true := by
  simp only [accepted, Bool.and_eq_true] at h
  simp only [acceptedBefore, Bool.and_eq_true]
  exact ⟨h.1.1.2, h.2⟩

end WvpV03

#print axioms WvpV03.claim_binding
#print axioms WvpV03.closed_kind_is_as_listed
#print axioms WvpV03.same_listing_same_records
#print axioms WvpV03.established_needs_pins
#print axioms WvpV03.no_pins_never_established
#print axioms WvpV03.added_checks_only_refuse

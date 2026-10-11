import Verified.Order

namespace Verified

/-!
Evidence semantics: authenticity is not verification.

A `Statement` is what an issuer asserted, together with the outcome of checking its signature
under the verifier's trust registry. Signature checking is not modelled; `authentic` is its
result. A `Model` says which issuers are authoritative for which source systems. Verification
is the judgement ⟨c, E, M, Π⟩ ⊢ Verified(c): some admissible statement in E satisfies the
contract under the order-v1 satisfaction predicate (Π).
-/

structure Statement where
  issuer : Nat
  evidence : Evidence
  authentic : Bool
  deriving DecidableEq, Repr

structure Model where
  authoritative : Nat → String → Bool

/-- Admissible evidence: authentic, and from an issuer the model makes authoritative for the
    evidence's source. Authenticity alone is not enough. -/
def Admissible (m : Model) (s : Statement) : Prop :=
  s.authentic = true ∧ m.authoritative s.issuer s.evidence.source = true

instance (m : Model) (s : Statement) : Decidable (Admissible m s) :=
  inferInstanceAs (Decidable (_ ∧ _))

def VerifiedBy (k : WorkContract) (c : Claim) (es : List Statement) (m : Model)
    (verifiedAt : Nat) : Prop :=
  ∃ s ∈ es, Admissible m s ∧ Satisfies k c s.evidence verifiedAt

/-- The executable procedure Π. -/
def verifyAll (k : WorkContract) (c : Claim) (es : List Statement) (m : Model)
    (verifiedAt : Nat) : Bool :=
  es.any fun s => decide (Admissible m s ∧ Satisfies k c s.evidence verifiedAt)

theorem verifyAll_iff (k : WorkContract) (c : Claim) (es : List Statement) (m : Model)
    (verifiedAt : Nat) : verifyAll k c es m verifiedAt = true ↔ VerifiedBy k c es m verifiedAt := by
  simp [verifyAll, VerifiedBy]

/-- Verification always rests on the contract's own satisfaction predicate. -/
theorem verified_requires_satisfaction (k : WorkContract) (c : Claim) (es : List Statement)
    (m : Model) (verifiedAt : Nat) (h : VerifiedBy k c es m verifiedAt) :
    ∃ s ∈ es, Satisfies k c s.evidence verifiedAt := by
  obtain ⟨s, member, _, satisfies⟩ := h
  exact ⟨s, member, satisfies⟩

/-- Without authentic evidence nothing is verified, whatever the statements say. -/
theorem unauthenticated_cannot_verify (k : WorkContract) (c : Claim) (es : List Statement)
    (m : Model) (verifiedAt : Nat) (none : ∀ s ∈ es, s.authentic = false) :
    ¬ VerifiedBy k c es m verifiedAt := by
  rintro ⟨s, member, ⟨authentic, _⟩, _⟩
  rw [none s member] at authentic
  contradiction

/-- Adding inadmissible statements (unauthenticated, or from non-authoritative issuers) can
    never turn an unverified claim into a verified one. -/
theorem inadmissible_additions_cannot_verify (k : WorkContract) (c : Claim)
    (es extra : List Statement) (m : Model) (verifiedAt : Nat)
    (inadmissible : ∀ s ∈ extra, ¬ Admissible m s)
    (h : VerifiedBy k c (es ++ extra) m verifiedAt) : VerifiedBy k c es m verifiedAt := by
  obtain ⟨s, member, admissible, satisfies⟩ := h
  rcases List.mem_append.mp member with inEs | inExtra
  · exact ⟨s, inEs, admissible, satisfies⟩
  · exact absurd admissible (inadmissible s inExtra)

-- Concrete witnesses: an authentic agent statement about the shipment does not verify the
-- claim, because the agent is not authoritative for the order system; the same observation
-- from the authoritative source does.
def erpIssuer : Nat := 1
def agentIssuer : Nat := 2
def erpAuthority : Model := ⟨fun issuer source => issuer == erpIssuer && source == "mock"⟩
def agentShipped : Statement := ⟨agentIssuer, { orderEvidence with source := "agent" }, true⟩
def erpShipped : Statement := ⟨erpIssuer, orderEvidence, true⟩

theorem authentic_agent_statement_does_not_verify :
    agentShipped.authentic = true ∧
      ¬ VerifiedBy orderContract orderClaim [agentShipped] erpAuthority 12 := by
  refine ⟨rfl, ?_⟩
  rw [← verifyAll_iff]
  decide

theorem authoritative_statement_verifies :
    VerifiedBy orderContract orderClaim [erpShipped] erpAuthority 12 := by
  rw [← verifyAll_iff]
  decide

end Verified

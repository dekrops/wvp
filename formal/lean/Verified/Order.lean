namespace Verified

-- Semantic model order-v1: identifiers and logical times abstract wire encodings.
inductive OrderState where
  | approved | shipped | cancelled
  deriving DecidableEq, Repr

structure Subject where
  system : String
  order : String
  deriving DecidableEq, Repr

structure WorkContract where
  id : Nat
  subject : Subject
  allowedFrom : List OrderState
  target : OrderState
  validFrom : Nat
  validUntil : Nat
  deriving DecidableEq, Repr

structure Claim where
  id : Nat
  contractId : Nat
  subject : Subject
  outcome : OrderState
  occurredAt : Nat
  deriving DecidableEq, Repr

structure Evidence where
  subject : Subject
  source : String
  before : OrderState
  after : OrderState
  observedAt : Nat
  ingestedAt : Nat
  deriving DecidableEq, Repr

-- Authenticity is an external trust obligation, not a theorem of this model.
-- This predicate evaluates supplied observations, including their claimed source.
def Satisfies (k : WorkContract) (c : Claim) (e : Evidence) (verifiedAt : Nat) : Prop :=
  c.contractId = k.id ∧ c.subject = k.subject ∧ e.subject = c.subject ∧
  e.source = c.subject.system ∧ c.outcome = k.target ∧
  e.before ∈ k.allowedFrom ∧ e.after = k.target ∧
  e.observedAt = c.occurredAt ∧ k.validFrom ≤ e.observedAt ∧
  e.observedAt < k.validUntil ∧ e.observedAt ≤ e.ingestedAt ∧ e.ingestedAt ≤ verifiedAt

instance (k : WorkContract) (c : Claim) (e : Evidence) (verifiedAt : Nat) :
    Decidable (Satisfies k c e verifiedAt) := inferInstanceAs (Decidable (_ ∧ _))

def verifies (k : WorkContract) (c : Claim) (e : Evidence) (verifiedAt : Nat) : Bool :=
  decide (Satisfies k c e verifiedAt)

theorem verification_sound (k : WorkContract) (c : Claim) (e : Evidence) (verifiedAt : Nat)
    (h : verifies k c e verifiedAt = true) : Satisfies k c e verifiedAt := by
  exact of_decide_eq_true h

def orderContract : WorkContract :=
  ⟨1, ⟨"mock", "ORDER-123"⟩, [.approved], .shipped, 0, 100⟩
def orderClaim : Claim := ⟨2, 1, orderContract.subject, .shipped, 10⟩
def orderEvidence : Evidence :=
  ⟨orderContract.subject, "mock", .approved, .shipped, 10, 11⟩

theorem order_fulfillment : verifies orderContract orderClaim orderEvidence 12 = true := by
  decide

theorem wrong_order_rejected :
    verifies orderContract orderClaim
      { orderEvidence with subject := ⟨"mock", "ORDER-999"⟩ } 12 = false := by
  decide

theorem disallowed_transition_rejected :
    verifies orderContract orderClaim { orderEvidence with before := .cancelled } 12 = false := by
  decide

end Verified

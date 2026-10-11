namespace Verified

/-!
Evidence-chain integrity, abstracted to sequence numbers and digest tokens.

A chain verified from genesis has contiguous sequence numbers 0, 1, 2, … in the presented
order, each step naming its predecessor's digest. Digest tokens stand for collision-resistant
hashes; signatures are assumed to have been checked. The second theorem is the documented
limit: every prefix of a valid chain is itself valid, so a truncated tail cannot be detected
from the chain alone.
-/

structure Link where
  seq : Nat
  prev : Option Nat
  digest : Nat
  deriving DecidableEq, Repr

def Linked : List Link → Prop
  | [] => True
  | [_] => True
  | a :: b :: rest => b.seq = a.seq + 1 ∧ b.prev = some a.digest ∧ Linked (b :: rest)

def ValidFromGenesis : List Link → Prop
  | [] => False
  | a :: rest => a.seq = 0 ∧ a.prev = none ∧ Linked (a :: rest)

theorem linked_sequence (a : Link) (rest : List Link) (h : Linked (a :: rest)) :
    ∀ (i : Nat) (hi : i < (a :: rest).length), ((a :: rest).get ⟨i, hi⟩).seq = a.seq + i := by
  induction rest generalizing a with
  | nil =>
    intro i hi
    simp at hi
    subst hi
    rfl
  | cons b rest ih =>
    intro i hi
    obtain ⟨step, _, tail⟩ := h
    cases i with
    | zero => rfl
    | succ j =>
      have := ih b tail j (by simpa using hi)
      simp only [List.get_cons_succ] at this ⊢
      rw [this, step]
      omega

/-- Valid chains are contiguous from zero in the presented order: no gaps, no reordering and no
    two steps with the same sequence number. -/
theorem valid_chain_is_contiguous (l : List Link) (h : ValidFromGenesis l) :
    ∀ (i : Nat) (hi : i < l.length), (l.get ⟨i, hi⟩).seq = i := by
  cases l with
  | nil => exact absurd h id
  | cons a rest =>
    obtain ⟨zero, _, linked⟩ := h
    intro i hi
    rw [linked_sequence a rest linked i hi, zero]
    omega

theorem linked_prefix (l r : List Link) (h : Linked (l ++ r)) : Linked l := by
  induction l with
  | nil => trivial
  | cons a rest ih =>
    cases rest with
    | nil => trivial
    | cons b rest' =>
      obtain ⟨step, prev, tail⟩ := h
      exact ⟨step, prev, ih tail⟩

/-- The truncation floor: removing a chain's tail leaves a valid chain. -/
theorem truncation_is_undetectable (l r : List Link) (nonempty : l ≠ [])
    (h : ValidFromGenesis (l ++ r)) : ValidFromGenesis l := by
  cases l with
  | nil => exact absurd rfl nonempty
  | cons a rest =>
    obtain ⟨zero, none, linked⟩ := h
    exact ⟨zero, none, linked_prefix (a :: rest) r linked⟩

end Verified

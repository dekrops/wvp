module

public import Veil

-- Reconstruct the solver's proofs in Lean, so that the kernel checks them.
set_option veil.smt.trust false

/-! One registry, one log, appended atomically. -/

veil module RegistryAtomic

type claim
type unit

-- A claim has been registered: its identifier is taken, for good.
relation registered (c : claim) : Bool
-- The unit a registered claim names.
relation names (c : claim) (u : unit) : Bool
-- The claim holds its unit: it is open, answered with evidence, or under an open dispute.
relation holds (c : claim) : Bool

#gen_state

after_init {
  registered C := false
  names C U := false
  holds C := false
}

-- The registry accepts a registration: the identifier is new and no claim holds the unit.
action register (c : claim) (u : unit) {
  require ¬ registered c
  require ∀ C, ¬ (holds C ∧ names C u)
  registered c := true
  names c u := true
  holds c := true
}

-- A claim stops holding its unit: refused, expired, withdrawn or superseded.
action release (c : claim) {
  require holds c
  holds c := false
}

safety [unit_exclusive] holds C1 ∧ holds C2 ∧ names C1 U ∧ names C2 U → C1 = C2

invariant [holders_are_registered] holds C → registered C
invariant [named_are_registered] names C U → registered C

#gen_spec

#model_check { claim := Fin 3, unit := Fin 2 } { }

sat trace [two_claims_one_unit_in_turn] {
  register
  release
  register
}

#check_invariants

end RegistryAtomic

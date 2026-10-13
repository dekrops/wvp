module

public import Veil

-- Reconstruct the solver's proofs in Lean, so that the kernel checks them.
set_option veil.smt.trust false

/-! The same replicas, where a replica accepts a registration only once it has observed every
entry there is: registrations are totally ordered, which is what one atomically appended log
gives. -/

veil module RegistryOrdered

type claim
type unit
type replica

relation registered (c : claim) : Bool
relation names (c : claim) (u : unit) : Bool
relation holds (c : claim) : Bool
relation observed (r : replica) (c : claim) : Bool
relation receipt (r : replica) (c : claim) : Bool

#gen_state

after_init {
  registered C := false
  names C U := false
  holds C := false
  observed R C := false
  receipt R C := false
}

action register (r : replica) (c : claim) (u : unit) {
  require ¬ registered c
  -- The added condition: nothing has been registered that this replica has not observed.
  require ∀ C, registered C → observed r C
  require ∀ C, ¬ (observed r C ∧ holds C ∧ names C u)
  registered c := true
  names c u := true
  holds c := true
  observed r c := true
  receipt r c := true
}

action observe (r other : replica) (c : claim) {
  require observed other c
  observed r c := true
}

action release (c : claim) {
  require holds c
  holds c := false
}

safety [unit_exclusive] holds C1 ∧ holds C2 ∧ names C1 U ∧ names C2 U → C1 = C2

invariant [holders_are_registered] holds C → registered C
invariant [named_are_registered] names C U → registered C
-- Found from a counterexample to induction: without it, a state with a receipt for a claim
-- that was never registered is not excluded, and registering that claim gives it a second.
invariant [receipts_are_registered] receipt R C → registered C
invariant [one_receipt_each] receipt R1 C ∧ receipt R2 C → R1 = R2

#gen_spec

#model_check { claim := Fin 3, unit := Fin 2, replica := Fin 2 } { }

#check_invariants

end RegistryOrdered

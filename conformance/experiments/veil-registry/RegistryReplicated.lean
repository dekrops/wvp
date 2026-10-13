module

public import Veil

/-! Several replicas of a registry, each accepting registrations on what it has observed.

This is not part of the protocol. Claim registration v1 defines one log. This module is the
deployment in which a registry is run as replicas that learn of each other's entries late, or in
which one registry shows two parties two logs: the two are the same model. -/

veil module RegistryReplicated

type claim
type unit
type replica

-- A claim has been registered somewhere: its identifier is taken.
relation registered (c : claim) : Bool
-- The unit a registered claim names.
relation names (c : claim) (u : unit) : Bool
-- The claim holds its unit.
relation holds (c : claim) : Bool
-- Replica `r` has observed the registration of `c`.
relation observed (r : replica) (c : claim) : Bool
-- Replica `r` issued the receipt for `c`.
relation receipt (r : replica) (c : claim) : Bool

#gen_state

after_init {
  registered C := false
  names C U := false
  holds C := false
  observed R C := false
  receipt R C := false
}

-- A replica accepts a registration when no claim it has observed holds the unit.
action register (r : replica) (c : claim) (u : unit) {
  require ¬ registered c
  require ∀ C, ¬ (observed r C ∧ holds C ∧ names C u)
  registered c := true
  names c u := true
  holds c := true
  observed r c := true
  receipt r c := true
}

-- A replica learns, some time later, of an entry another replica accepted.
action observe (r other : replica) (c : claim) {
  require observed other c
  observed r c := true
}

action release (c : claim) {
  require holds c
  holds c := false
}

safety [unit_exclusive] holds C1 ∧ holds C2 ∧ names C1 U ∧ names C2 U → C1 = C2

#gen_spec

-- Expected to be violated: two replicas, two claims, one unit.
#model_check { claim := Fin 2, unit := Fin 1, replica := Fin 2 } { }

end RegistryReplicated

import Verified.Contract.Semantics

/-!
When a requirement applies, as RFC 0012 proposes it.

A requirement may carry a condition, `appliesWhen`. Where the condition is `FALSE`, the requirement
is `NOT_APPLICABLE`: it neither holds nor fails, and it never makes a decision `CONTRADICTED`.
Where it is `unknown`, so is the requirement, since it may yet apply. Where every requirement is
`NOT_APPLICABLE`, so is the decision.

The model is generic in the predicate language: `eval` is any evaluation of a predicate to a
`Truth`. Language 2 (RFC 0008) is the instance `Examples.lean` uses, and the stability theorem
needs only that `eval` is stable along more evidence, which RFC 0008, RFC 0009 and RFC 0011 each
prove of their own.
-/

namespace Applies

open Verified.Contract

/-- A requirement's value. -/
inductive Result where
  | true | false | unknown | notApplicable
  deriving DecidableEq, Repr

/-- A contract's decision. -/
inductive Outcome where
  | supported | contradicted | undetermined | notApplicable
  deriving DecidableEq, Repr

def Result.ofTruth : Truth → Result
  | .true => .true
  | .false => .false
  | .unknown => .unknown

def Outcome.ofDecision : Decision → Outcome
  | .supported => .supported
  | .contradicted => .contradicted
  | .undetermined => .undetermined

/-- A requirement: what must hold, and, optionally, when it applies. -/
structure Requirement (P : Type) where
  appliesWhen : Option P
  holds : P

/-- A requirement's value, from its predicates' values. -/
def result {P : Type} (eval : P → Truth) (requirement : Requirement P) : Result :=
  match requirement.appliesWhen with
  | none => .ofTruth (eval requirement.holds)
  | some condition =>
    match eval condition with
    | .true => .ofTruth (eval requirement.holds)
    | .false => .notApplicable
    | .unknown => .unknown

/-- The decision over the requirements' values: as Language 1 decides, except that requirements
    that do not apply are left out, and a contract none of whose requirements applies is
    `NOT_APPLICABLE`. -/
def decideAll (results : List Result) : Outcome :=
  if Result.false ∈ results then .contradicted
  else if Result.unknown ∈ results then .undetermined
  else if !results.isEmpty && results.all (· == .notApplicable) then .notApplicable
  else .supported

def evaluate {P : Type} (eval : P → Truth) (requirements : List (Requirement P)) : Outcome :=
  decideAll (requirements.map (result eval))

end Applies

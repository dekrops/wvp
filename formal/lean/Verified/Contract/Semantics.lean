import Verified.Contract.Truth

namespace Verified.Contract

/-!
Work Contract Language 1: syntax, environments and evaluation.

This file is the definition. It corresponds to sections 3, 4 and 7 (steps 7 and 8) of
protocols/work-contract/v1/SPEC.md. Two things differ from the wire form, both by choice:
`and` and `or` are binary here (the wire form's lists are folded, which is the same function
because the connectives are associative), and an environment is the one evaluation sees, after
acceptance, conformance and conflict resolution have produced the records of each kind and the
set of closed kinds.
-/

inductive Ty where
  | text | bool | int | time
  | decimal (scale : Nat)
  | money (currency : String) (scale : Nat)
  deriving DecidableEq, Repr

/-- Integers, times, decimals and money are all whole numbers of the type's smallest unit. -/
inductive Value where
  | text (value : String)
  | bool (value : Bool)
  | num (value : Int)
  deriving DecidableEq, Repr

inductive Op where
  | eq | ne | lt | le | gt | ge
  deriving DecidableEq, Repr

inductive Term where
  | lit (ty : Ty) (value : Value)
  | input (name : String)
  | param (name : String)
  | field (var : String) (name : String)
  deriving DecidableEq, Repr

inductive Pred where
  | cmp (op : Op) (left right : Term)
  | and (left right : Pred)
  | or (left right : Pred)
  | not (arg : Pred)
  | ex (var kind : String) (body : Pred)
  | all (var kind : String) (body : Pred)
  deriving Repr

/-- A record: the fields it carries. An optional field it does not carry is simply not listed. -/
structure Record where
  fields : List (String × Value)
  deriving Repr

def Record.get (record : Record) (field : String) : Option Value :=
  (record.fields.find? (·.1 == field)).map (·.2)

/-- What evaluation sees. `closed kind` says an accepted source declared its records of the kind
    complete as of the cutoff, and no unsettled conflict reopened it. -/
structure Env where
  inputs : String → Option Value
  params : String → Option Value
  records : String → List Record
  closed : String → Bool

/-- The records bound by the enclosing quantifiers, innermost first. -/
abbrev Scope := List (String × Record)

def Scope.get (scope : Scope) (var : String) : Option Record :=
  (scope.find? (·.1 == var)).map (·.2)

/-- `none` is a value that is not there: an absent optional field. -/
def Term.eval (env : Env) (scope : Scope) : Term → Option Value
  | .lit _ value => some value
  | .input name => env.inputs name
  | .param name => env.params name
  | .field var name => (Scope.get scope var).bind (·.get name)

def Truth.of (b : Bool) : Truth := if b then .true else .false

/-- Comparison of two present values. On values of different shapes, or an order on text or
    booleans, the answer is `unknown`; `wellTyped_safe` shows a well-typed contract never asks. -/
def compare : Op → Value → Value → Truth
  | .eq, .num a, .num b => Truth.of (a == b)
  | .ne, .num a, .num b => Truth.of (a != b)
  | .lt, .num a, .num b => Truth.of (a < b)
  | .le, .num a, .num b => Truth.of (a ≤ b)
  | .gt, .num a, .num b => Truth.of (a > b)
  | .ge, .num a, .num b => Truth.of (a ≥ b)
  | .eq, .text a, .text b => Truth.of (a == b)
  | .ne, .text a, .text b => Truth.of (a != b)
  | .eq, .bool a, .bool b => Truth.of (a == b)
  | .ne, .bool a, .bool b => Truth.of (a != b)
  | _, _, _ => .unknown

def Pred.eval (env : Env) : Pred → Scope → Truth
  | .cmp op left right, scope =>
    match left.eval env scope, right.eval env scope with
    | some a, some b => compare op a b
    | _, _ => .unknown
  | .and left right, scope => (left.eval env scope).and (right.eval env scope)
  | .or left right, scope => (left.eval env scope).or (right.eval env scope)
  | .not arg, scope => (arg.eval env scope).not
  | .ex var kind body, scope =>
    -- A witness settles it. Without one, only a complete listing shows there is none.
    let seen := Truth.any ((env.records kind).map fun record => body.eval env ((var, record) :: scope))
    if seen = .false ∧ env.closed kind = false then .unknown else seen
  | .all var kind body, scope =>
    -- A counterexample settles it. Without one, only a complete listing shows there is none.
    let seen := Truth.all ((env.records kind).map fun record => body.eval env ((var, record) :: scope))
    if seen = .true ∧ env.closed kind = false then .unknown else seen

inductive Decision where
  | supported | contradicted | undetermined
  deriving DecidableEq, Repr

/-- The decision over the values of all requirements (section 7, step 8). -/
def decide (values : List Truth) : Decision :=
  if Truth.false ∈ values then .contradicted
  else if Truth.unknown ∈ values then .undetermined
  else .supported

/-- A contract's requirements, evaluated in an environment with nothing bound. -/
def evaluate (env : Env) (requirements : List Pred) : Decision :=
  decide (requirements.map fun requirement => requirement.eval env [])

end Verified.Contract

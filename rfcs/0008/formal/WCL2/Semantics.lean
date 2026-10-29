import Verified.Contract.Theorems

/-!
Work Contract Language 2, as RFC 0008 proposes it: Work Contract Language 1 with arithmetic on
numbers and with aggregates (`count`, `sum`) over the records of a kind.

It reuses Language 1's values, records, environments, scopes, comparisons and truth values
(formal/lean/Verified/Contract). What is new:

* Terms may add, subtract, scale by a whole number and take the absolute value. Every number in
  the language is already a whole number of its type's smallest unit (an integer, a time, a
  decimal of fixed scale, money in one currency), so this is exact integer arithmetic. There is
  no division and no rounding. Whether two operands have one unit is the typing's concern, as
  it is for comparison in Language 1.
* A requirement may compare an aggregate of a kind's records with a term: how many records
  satisfy a body (`count`), or the sum of a field over them (`sum`). An aggregate has a value
  only when the kind is closed and the body is definite for every record; otherwise the
  comparison is `unknown`. A count over a listing nobody declared complete is not a count.
-/

namespace WCL2

open Verified.Contract

inductive Term where
  | lit (ty : Ty) (value : Value)
  | input (name : String)
  | param (name : String)
  | field (var : String) (name : String)
  | add (left right : Term)
  | sub (left right : Term)
  | scale (factor : Int) (arg : Term)
  | abs (arg : Term)
  deriving Repr

inductive Aggregate where
  | count
  | sum (field : String)
  deriving DecidableEq, Repr

inductive Pred where
  | cmp (op : Op) (left right : Term)
  | and (left right : Pred)
  | or (left right : Pred)
  | not (arg : Pred)
  | ex (var kind : String) (body : Pred)
  | all (var kind : String) (body : Pred)
  /-- `fn` over the records of `kind` for which `body` holds, compared by `op` with `bound`. -/
  | agg (fn : Aggregate) (var kind : String) (body : Pred) (op : Op) (bound : Term)
  deriving Repr

/-- A number, or nothing: an absent value, or a value that is not a number. -/
def number : Option Value → Option Int
  | some (.num n) => some n
  | _ => none

def Term.eval (env : Env) (scope : Scope) : Term → Option Value
  | .lit _ value => some value
  | .input name => env.inputs name
  | .param name => env.params name
  | .field var name => (Scope.get scope var).bind (·.get name)
  | .add left right =>
    match number (left.eval env scope), number (right.eval env scope) with
    | some a, some b => some (.num (a + b))
    | _, _ => none
  | .sub left right =>
    match number (left.eval env scope), number (right.eval env scope) with
    | some a, some b => some (.num (a - b))
    | _, _ => none
  | .scale factor arg => (number (arg.eval env scope)).map fun a => .num (factor * a)
  | .abs arg => (number (arg.eval env scope)).map fun a => .num (if a < 0 then -a else a)

/-- The sum of numbers, or nothing if any is missing. -/
def sumOf : List (Option Int) → Option Int
  | [] => some 0
  | x :: rest =>
    match x, sumOf rest with
    | some a, some b => some (a + b)
    | _, _ => none

/-- Each record of a kind with the value of the body for it. -/
abbrev Judged := List (Record × Truth)

/-- The records the body holds for. -/
def selected (judged : Judged) : List Record :=
  (judged.filter fun pair => decide (pair.2 = .true)).map (·.1)

/-- The body is settled for every record. -/
def definite (judged : Judged) : Bool :=
  judged.all fun pair => decide (pair.2 ≠ .unknown)

/-- The aggregate's value: only over a closed kind, and only when every body is settled. -/
def Aggregate.value (fn : Aggregate) (closed : Bool) (judged : Judged) : Option Int :=
  if closed = true ∧ definite judged = true then
    match fn with
    | .count => some (selected judged).length
    | .sum field => sumOf ((selected judged).map fun record => number (record.get field))
  else none

def Pred.eval (env : Env) : Pred → Scope → Truth
  | .cmp op left right, scope =>
    match left.eval env scope, right.eval env scope with
    | some a, some b => compare op a b
    | _, _ => .unknown
  | .and left right, scope => (left.eval env scope).and (right.eval env scope)
  | .or left right, scope => (left.eval env scope).or (right.eval env scope)
  | .not arg, scope => (arg.eval env scope).not
  | .ex var kind body, scope =>
    let seen := Truth.any ((env.records kind).map fun record => body.eval env ((var, record) :: scope))
    if seen = .false ∧ env.closed kind = false then .unknown else seen
  | .all var kind body, scope =>
    let seen := Truth.all ((env.records kind).map fun record => body.eval env ((var, record) :: scope))
    if seen = .true ∧ env.closed kind = false then .unknown else seen
  | .agg fn var kind body op bound, scope =>
    let judged : Judged :=
      (env.records kind).map fun record => (record, body.eval env ((var, record) :: scope))
    match fn.value (env.closed kind) judged, bound.eval env scope with
    | some n, some b => compare op (.num n) b
    | _, _ => .unknown

/-- The decision over a contract's requirements, as Language 1 decides it. -/
def evaluate (env : Env) (requirements : List Pred) : Decision :=
  Verified.Contract.decide (requirements.map fun requirement => requirement.eval env [])

end WCL2

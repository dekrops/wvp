import WCL2T.Semantics

/-!
Completeness per group, as the draft RFC proposes it, on top of RFC 0011 (aggregates as terms).

Today a completeness statement closes a whole kind: "these are all the payments". One payment
that couldn't be read leaves the kind open, so every check over payments is `unknown`, for every
invoice. Here a statement may instead close one **group** of a kind: "these are all the payments
whose `invoice` is INV-01". And a quantifier or aggregate may say it reads one group only
(`per`): "the payments of this invoice". Such a quantifier ranges over the records of the group,
and is closed when the kind is closed or when that group is.

What is new, against `WCL2T.Semantics`:

* the environment carries `groups kind field value`: whether a source declared complete every
  record of `kind` whose `field` is `value`. A statement may list the values it covers, or cover
  every value except some (`except`): both are such a function;
* `ex`, `all` and `agg` carry `group : Option String` and `key : Term`. With `group = none` they
  are RFC 0011's, and `key` is not read. With `group = some field` they range over the records
  whose `field` equals `key`'s value. If `key` has no value, the group is unknown: the quantifier
  is `unknown` and the aggregate has no value.
-/

namespace WCL2G

open Verified.Contract
open WCL2 (Aggregate Judged number)

/-- An environment, and the groups declared complete: `groups kind field value` says a source
    declared complete every record of `kind` whose `field` is `value`. -/
structure GEnv where
  base : Env
  groups : String → String → Value → Bool

/-- The records a quantifier ranges over, and whether that listing is closed. -/
def listing (env : GEnv) (kind : String) : Option String → Option Value → Bool × List Record
  | none, _ => (env.base.closed kind, env.base.records kind)
  | some _, none => (false, [])
  | some field, some value =>
    (env.base.closed kind || env.groups kind field value,
      (env.base.records kind).filter fun record => decide (record.get field = some value))

mutual
  inductive Term where
    | lit (ty : Ty) (value : Value)
    | input (name : String)
    | param (name : String)
    | field (var : String) (name : String)
    | add (left right : Term)
    | sub (left right : Term)
    | scale (factor : Int) (arg : Term)
    | abs (arg : Term)
    | mul (left right : Term)
    | agg (fn : Aggregate) (var kind : String) (group : Option String) (key : Term) (body : Pred)

  inductive Pred where
    | cmp (op : Op) (left right : Term)
    | and (left right : Pred)
    | or (left right : Pred)
    | not (arg : Pred)
    | ex (var kind : String) (group : Option String) (key : Term) (body : Pred)
    | all (var kind : String) (group : Option String) (key : Term) (body : Pred)
    | agg (fn : Aggregate) (var kind : String) (group : Option String) (key : Term) (body : Pred)
        (op : Op) (bound : Term)
end

mutual
  def Term.eval (env : GEnv) : Term → Scope → Option Value
    | .lit _ value, _ => some value
    | .input name, _ => env.base.inputs name
    | .param name, _ => env.base.params name
    | .field var name, scope => (Scope.get scope var).bind (·.get name)
    | .add left right, scope =>
      match number (left.eval env scope), number (right.eval env scope) with
      | some a, some b => some (.num (a + b))
      | _, _ => none
    | .sub left right, scope =>
      match number (left.eval env scope), number (right.eval env scope) with
      | some a, some b => some (.num (a - b))
      | _, _ => none
    | .scale factor arg, scope => (number (arg.eval env scope)).map fun a => .num (factor * a)
    | .abs arg, scope => (number (arg.eval env scope)).map fun a => .num (if a < 0 then -a else a)
    | .mul left right, scope =>
      match number (left.eval env scope), number (right.eval env scope) with
      | some a, some b => some (.num (a * b))
      | _, _ => none
    | .agg fn var kind group key body, scope =>
      let l := listing env kind group (key.eval env scope)
      (fn.value l.1 (l.2.map fun record => (record, body.eval env ((var, record) :: scope)))).map .num

  def Pred.eval (env : GEnv) : Pred → Scope → Truth
    | .cmp op left right, scope =>
      match left.eval env scope, right.eval env scope with
      | some a, some b => compare op a b
      | _, _ => .unknown
    | .and left right, scope => (left.eval env scope).and (right.eval env scope)
    | .or left right, scope => (left.eval env scope).or (right.eval env scope)
    | .not arg, scope => (arg.eval env scope).not
    | .ex var kind group key body, scope =>
      let l := listing env kind group (key.eval env scope)
      let seen := Truth.any (l.2.map fun record => body.eval env ((var, record) :: scope))
      if seen = .false ∧ l.1 = false then .unknown else seen
    | .all var kind group key body, scope =>
      let l := listing env kind group (key.eval env scope)
      let seen := Truth.all (l.2.map fun record => body.eval env ((var, record) :: scope))
      if seen = .true ∧ l.1 = false then .unknown else seen
    | .agg fn var kind group key body op bound, scope =>
      let l := listing env kind group (key.eval env scope)
      let judged : Judged := l.2.map fun record => (record, body.eval env ((var, record) :: scope))
      match fn.value l.1 judged, bound.eval env scope with
      | some n, some b => compare op (.num n) b
      | _, _ => .unknown
end

/-- The decision over a contract's requirements, as Language 1 decides it. -/
def evaluate (env : GEnv) (requirements : List Pred) : Decision :=
  Verified.Contract.decide (requirements.map fun requirement => requirement.eval env [])

end WCL2G

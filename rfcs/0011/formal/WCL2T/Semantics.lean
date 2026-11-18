import WCL2.Semantics

/-!
Work Contract Language 2 with aggregates as terms, as RFC 0011 proposes it.

RFC 0008 lets a requirement compare one aggregate with a term. Here an aggregate **is** a term,
so it can be added to another aggregate, scaled, compared with an aggregate, and used anywhere a
number can. Two P2P controls need this: "the invoice's net and tax add up to its gross"
(Σ(net + tax) = gross, two sums added) and the cumulative three-way match (what was invoiced
against an order, in all, is at most what was received: a sum compared with a sum). Terms may also
multiply (`mul`), so a tax rate can be read from the invoice rather than listed in the contract.

An aggregate term has RFC 0008's value: only over a closed kind with every body settled, otherwise
none, so a comparison that reads it is `unknown`. RFC 0008's `agg` predicate is kept, and means
exactly the comparison of the aggregate term with its bound (`agg_is_cmp`).
-/

namespace WCL2T

open Verified.Contract
open WCL2 (Aggregate Judged number)

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
    /-- The product of two numbers (new). The typing allows a product only where one factor is
        a pure number (an `int`, or a `decimal` used as a rate), so units stay meaningful. -/
    | mul (left right : Term)
    /-- `fn` over the records of `kind` for which `body` holds, as a number (new). -/
    | agg (fn : Aggregate) (var kind : String) (body : Pred)

  inductive Pred where
    | cmp (op : Op) (left right : Term)
    | and (left right : Pred)
    | or (left right : Pred)
    | not (arg : Pred)
    | ex (var kind : String) (body : Pred)
    | all (var kind : String) (body : Pred)
    | agg (fn : Aggregate) (var kind : String) (body : Pred) (op : Op) (bound : Term)
end

mutual
  def Term.eval (env : Env) : Term → Scope → Option Value
    | .lit _ value, _ => some value
    | .input name, _ => env.inputs name
    | .param name, _ => env.params name
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
    | .agg fn var kind body, scope =>
      (fn.value (env.closed kind)
        ((env.records kind).map fun record => (record, body.eval env ((var, record) :: scope)))).map .num

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
end

/-- The decision over a contract's requirements, as Language 1 decides it. -/
def evaluate (env : Env) (requirements : List Pred) : Decision :=
  Verified.Contract.decide (requirements.map fun requirement => requirement.eval env [])

end WCL2T

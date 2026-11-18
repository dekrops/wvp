import WCL2T.Semantics
import WCL2.Theorems

/-!
What is proved about aggregates as terms, as `Semantics.lean` defines them. Theorems about the
model, not about an implementation, the wire form or the typing.
-/

namespace WCL2T

open Verified.Contract
open WCL2 (Aggregate Judged definite number)

/-! ## RFC 0011 extends RFC 0008 -/

def Term.ofL2 : WCL2.Term → Term
  | .lit ty value => .lit ty value
  | .input name => .input name
  | .param name => .param name
  | .field var name => .field var name
  | .add left right => .add (Term.ofL2 left) (Term.ofL2 right)
  | .sub left right => .sub (Term.ofL2 left) (Term.ofL2 right)
  | .scale factor arg => .scale factor (Term.ofL2 arg)
  | .abs arg => .abs (Term.ofL2 arg)

def Pred.ofL2 : WCL2.Pred → Pred
  | .cmp op left right => .cmp op (Term.ofL2 left) (Term.ofL2 right)
  | .and left right => .and (Pred.ofL2 left) (Pred.ofL2 right)
  | .or left right => .or (Pred.ofL2 left) (Pred.ofL2 right)
  | .not arg => .not (Pred.ofL2 arg)
  | .ex var kind body => .ex var kind (Pred.ofL2 body)
  | .all var kind body => .all var kind (Pred.ofL2 body)
  | .agg fn var kind body op bound => .agg fn var kind (Pred.ofL2 body) op (Term.ofL2 bound)

theorem term_ofL2_eval (env : Env) (term : WCL2.Term) :
    ∀ scope, (Term.ofL2 term).eval env scope = term.eval env scope := by
  induction term with
  | lit => intro scope; rfl
  | input => intro scope; rfl
  | param => intro scope; rfl
  | field => intro scope; rfl
  | add left right ihl ihr =>
    intro scope; simp only [Term.ofL2, Term.eval, WCL2.Term.eval, ihl, ihr]
    cases number (WCL2.Term.eval env scope left) <;> cases number (WCL2.Term.eval env scope right) <;> rfl
  | sub left right ihl ihr =>
    intro scope; simp only [Term.ofL2, Term.eval, WCL2.Term.eval, ihl, ihr]
    cases number (WCL2.Term.eval env scope left) <;> cases number (WCL2.Term.eval env scope right) <;> rfl
  | scale factor arg ih =>
    intro scope; simp only [Term.ofL2, Term.eval, WCL2.Term.eval, ih]
  | abs arg ih =>
    intro scope; simp only [Term.ofL2, Term.eval, WCL2.Term.eval, ih]

/-- Every RFC 0008 requirement means the same here: the same value in every environment and
    scope. Nothing a Language 2 contract decides is decided differently. -/
theorem extends_language_2 (env : Env) (pred : WCL2.Pred) :
    ∀ scope, (Pred.ofL2 pred).eval env scope = pred.eval env scope := by
  induction pred with
  | cmp op left right =>
    intro scope
    simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, term_ofL2_eval]
    cases WCL2.Term.eval env scope left <;> cases WCL2.Term.eval env scope right <;> rfl
  | and left right ihl ihr =>
    intro scope; simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, ihl, ihr]
  | or left right ihl ihr =>
    intro scope; simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, ihl, ihr]
  | not arg ih =>
    intro scope; simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, ih]
  | ex var kind body ih =>
    intro scope; simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, ih]
  | all var kind body ih =>
    intro scope; simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, ih]
  | agg fn var kind body op bound ih =>
    intro scope; simp only [Pred.ofL2, Pred.eval, WCL2.Pred.eval, ih, term_ofL2_eval]
    cases fn.value (env.closed kind)
        ((env.records kind).map fun record => (record, WCL2.Pred.eval env body ((var, record) :: scope))) <;>
      cases WCL2.Term.eval env scope bound <;> rfl

/-- An RFC 0008 contract has the same decision here. -/
theorem same_decision_as_language_2 (env : Env) (requirements : List WCL2.Pred) :
    evaluate env (requirements.map Pred.ofL2) = WCL2.evaluate env requirements := by
  simp only [evaluate, WCL2.evaluate, List.map_map]
  congr 1
  apply List.map_congr_left
  intro pred _
  exact extends_language_2 env pred []

/-! ## RFC 0008's `agg` is a comparison with an aggregate term -/

/-- `agg fn … op bound` is exactly `cmp op (agg fn …) bound`: the predicate form is kept for
    compatibility, and adds nothing. -/
theorem agg_is_cmp (env : Env) (fn : Aggregate) (var kind : String) (body : Pred) (op : Op)
    (bound : Term) (scope : Scope) :
    (Pred.agg fn var kind body op bound).eval env scope =
      (Pred.cmp op (Term.agg fn var kind body) bound).eval env scope := by
  simp only [Pred.eval, Term.eval]
  cases fn.value (env.closed kind)
      ((env.records kind).map fun record => (record, body.eval env ((var, record) :: scope))) <;>
    cases bound.eval env scope <;> rfl

/-! ## An aggregate term counts only complete listings -/

/-- An aggregate term with a value was taken over a closed kind, every body settled. -/
theorem agg_value_requires_closed (env : Env) (fn : Aggregate) (var kind : String) (body : Pred)
    (scope : Scope) (v : Value) (h : (Term.agg fn var kind body).eval env scope = some v) :
    env.closed kind = true ∧
      ∀ record ∈ env.records kind, body.eval env ((var, record) :: scope) ≠ .unknown := by
  simp only [Term.eval] at h
  cases hv : fn.value (env.closed kind)
      ((env.records kind).map fun record => (record, body.eval env ((var, record) :: scope))) with
  | none => rw [hv] at h; contradiction
  | some n =>
    obtain ⟨closed, settled⟩ := WCL2.aggregate_value_requires_closed fn _ _ n hv
    refine ⟨closed, fun record member => ?_⟩
    have := List.all_eq_true.mp settled (record, body.eval env ((var, record) :: scope))
      (List.mem_map.mpr ⟨record, member, rfl⟩)
    simpa using this

/-- Fail closed: over a kind no source declared complete, an aggregate term has no value, so
    every comparison, sum or product that reads it is unknown or has no value either. -/
theorem agg_open_kind_has_no_value (env : Env) (fn : Aggregate) (var kind : String) (body : Pred)
    (scope : Scope) (open_ : env.closed kind = false) :
    (Term.agg fn var kind body).eval env scope = none := by
  cases h : (Term.agg fn var kind body).eval env scope with
  | none => rfl
  | some v =>
    have := (agg_value_requires_closed env fn var kind body scope v h).1
    rw [open_] at this
    contradiction

/-- A comparison reading a term with no value is unknown: missing evidence never becomes a
    `TRUE` or a `FALSE` by way of arithmetic. -/
theorem cmp_unknown_of_none (env : Env) (op : Op) (left right : Term) (scope : Scope)
    (h : left.eval env scope = none ∨ right.eval env scope = none) :
    (Pred.cmp op left right).eval env scope = .unknown := by
  simp only [Pred.eval]
  rcases h with h | h <;> rw [h] <;> cases left.eval env scope <;> cases right.eval env scope <;>
    simp_all

/-- Arithmetic over a term with no value has no value. -/
theorem add_none (env : Env) (left right : Term) (scope : Scope)
    (h : left.eval env scope = none ∨ right.eval env scope = none) :
    (Term.add left right).eval env scope = none := by
  simp only [Term.eval]
  rcases h with h | h <;> rw [h] <;> cases number (left.eval env scope) <;>
    cases number (right.eval env scope) <;> simp_all [number]

theorem mul_none (env : Env) (left right : Term) (scope : Scope)
    (h : left.eval env scope = none ∨ right.eval env scope = none) :
    (Term.mul left right).eval env scope = none := by
  simp only [Term.eval]
  rcases h with h | h <;> rw [h] <;> cases number (left.eval env scope) <;>
    cases number (right.eval env scope) <;> simp_all [number]

end WCL2T

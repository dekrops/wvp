import Verified.Contract.Reference

/-!
A first correspondence between what the reference evaluator runs and the semantic definition.

The specification writes `and` and `or` over lists (section 7.7). The definition (`Pred`) has
binary connectives, and the evaluator turns one into the other with `Reference.lower` before it
calls `Pred.eval`. `lower` is a `partial` definition, so Lean gives it no equations and nothing
can be proved about it.

This file gives the wire form its own meaning, written from the specification (`WPred.eval`),
gives the lowering a total definition (`lowerTotal`), and proves that lowering preserves meaning.
`Lowering.lean` checks, on every published contract, that `lowerTotal` and the evaluator's
`lower` produce the same term. That last step is a test: it cannot be a theorem while `lower`
is partial.
-/

namespace Refinement

open Verified.Contract
open Verified.Contract.Reference

/-! ## The wire form's own meaning -/

mutual
/-- The value of a predicate in wire form, as the specification states it: `and` is the
    conjunction of all its arguments, `or` the disjunction. -/
def evalWire (env : Env) : WPred → Scope → Truth
  | .cmp op left right, scope => (Pred.cmp op left right).eval env scope
  | .and args, scope => Truth.all (evalWireList env args scope)
  | .or args, scope => Truth.any (evalWireList env args scope)
  | .not arg, scope => (evalWire env arg scope).not
  | .ex var kind body, scope =>
    let seen := Truth.any (evalWireOver env body var scope (env.records kind))
    if seen = .false ∧ env.closed kind = false then .unknown else seen
  | .all var kind body, scope =>
    let seen := Truth.all (evalWireOver env body var scope (env.records kind))
    if seen = .true ∧ env.closed kind = false then .unknown else seen

def evalWireList (env : Env) : List WPred → Scope → List Truth
  | [], _ => []
  | p :: ps, scope => evalWire env p scope :: evalWireList env ps scope

/-- A quantifier's body, once for each record. -/
def evalWireOver (env : Env) (body : WPred) (var : String) (scope : Scope) :
    List Record → List Truth
  | [] => []
  | record :: records =>
    evalWire env body ((var, record) :: scope) :: evalWireOver env body var scope records
end

/-! ## A total lowering -/

/-- What an empty conjunction lowers to: a comparison that is true. -/
def emptyAnd : Pred := .cmp .eq (.lit .bool (.bool true)) (.lit .bool (.bool true))

/-- What an empty disjunction lowers to: a comparison that is false. -/
def emptyOr : Pred := .cmp .eq (.lit .bool (.bool true)) (.lit .bool (.bool false))

mutual
/-- `Reference.lower`, defined by structural recursion. -/
def lowerTotal : WPred → Pred
  | .cmp o l r => .cmp o l r
  | .and args => match lowerList args with
    | [] => emptyAnd
    | first :: rest => rest.foldl .and first
  | .or args => match lowerList args with
    | [] => emptyOr
    | first :: rest => rest.foldl .or first
  | .not arg => .not (lowerTotal arg)
  | .ex v k body => .ex v k (lowerTotal body)
  | .all v k body => .all v k (lowerTotal body)

def lowerList : List WPred → List Pred
  | [] => []
  | p :: ps => lowerTotal p :: lowerList ps
end

/-! ## Lowering preserves meaning -/

theorem and_assoc (a b c : Truth) : (a.and b).and c = a.and (b.and c) := by
  cases a <;> cases b <;> cases c <;> rfl

theorem or_assoc (a b c : Truth) : (a.or b).or c = a.or (b.or c) := by
  cases a <;> cases b <;> cases c <;> rfl

theorem and_true (a : Truth) : a.and .true = a := by cases a <;> rfl

theorem or_false (a : Truth) : a.or .false = a := by cases a <;> rfl

/-- A left-nested conjunction means the conjunction of its parts. -/
theorem foldl_and_eval (env : Env) (scope : Scope) (rest : List Pred) (first : Pred) :
    (rest.foldl .and first).eval env scope =
      Truth.all (first.eval env scope :: rest.map (·.eval env scope)) := by
  induction rest generalizing first with
  | nil => simp [Truth.all, and_true]
  | cons next rest ih =>
    simp only [List.foldl_cons, List.map_cons]
    rw [ih]
    simp [Truth.all, Pred.eval, and_assoc]

theorem foldl_or_eval (env : Env) (scope : Scope) (rest : List Pred) (first : Pred) :
    (rest.foldl .or first).eval env scope =
      Truth.any (first.eval env scope :: rest.map (·.eval env scope)) := by
  induction rest generalizing first with
  | nil => simp [Truth.any, or_false]
  | cons next rest ih =>
    simp only [List.foldl_cons, List.map_cons]
    rw [ih]
    simp [Truth.any, Pred.eval, or_assoc]

theorem emptyAnd_eval (env : Env) (scope : Scope) : emptyAnd.eval env scope = .true := by
  rfl

theorem emptyOr_eval (env : Env) (scope : Scope) : emptyOr.eval env scope = .false := by
  rfl

mutual
/-- **Lowering preserves meaning.** For every predicate in wire form, every environment and
    every scope, the lowered predicate has, under the semantic definition, the value the wire
    form has under the specification's reading of `and` and `or`. -/
theorem lowerTotal_eval (env : Env) : ∀ (p : WPred) (scope : Scope),
    (lowerTotal p).eval env scope = evalWire env p scope
  | .cmp _ _ _, _ => by simp [lowerTotal, evalWire]
  | .and args, scope => by
    have ih := lowerList_eval env args scope
    simp only [lowerTotal, evalWire]
    cases h : lowerList args with
    | nil => rw [h] at ih; simp [← ih, emptyAnd_eval, Truth.all]
    | cons first rest => rw [h] at ih; simp [foldl_and_eval, ← ih]
  | .or args, scope => by
    have ih := lowerList_eval env args scope
    simp only [lowerTotal, evalWire]
    cases h : lowerList args with
    | nil => rw [h] at ih; simp [← ih, emptyOr_eval, Truth.any]
    | cons first rest => rw [h] at ih; simp [foldl_or_eval, ← ih]
  | .not arg, scope => by simp [lowerTotal, evalWire, Pred.eval, lowerTotal_eval env arg scope]
  | .ex var kind body, scope => by
    simp only [lowerTotal, evalWire, Pred.eval]
    rw [lowerOver_eval env body var scope (env.records kind)]
  | .all var kind body, scope => by
    simp only [lowerTotal, evalWire, Pred.eval]
    rw [lowerOver_eval env body var scope (env.records kind)]

theorem lowerList_eval (env : Env) : ∀ (ps : List WPred) (scope : Scope),
    (lowerList ps).map (·.eval env scope) = evalWireList env ps scope
  | [], _ => by simp [lowerList, evalWireList]
  | p :: ps, scope => by
    simp [lowerList, evalWireList, lowerTotal_eval env p scope, lowerList_eval env ps scope]

theorem lowerOver_eval (env : Env) (body : WPred) (var : String) (scope : Scope) :
    ∀ records : List Record,
      (records.map fun record => (lowerTotal body).eval env ((var, record) :: scope)) =
        evalWireOver env body var scope records
  | [] => by simp [evalWireOver]
  | record :: records => by
    simp [evalWireOver, lowerTotal_eval env body ((var, record) :: scope),
      lowerOver_eval env body var scope records]
end

/-- So the decision over lowered requirements is the decision over their wire forms. -/
theorem lowered_decision (env : Env) (requirements : List WPred) :
    evaluate env (requirements.map lowerTotal) =
      decide (requirements.map fun p => evalWire env p []) := by
  simp [evaluate, List.map_map, Function.comp_def, lowerTotal_eval]

/-! ## What the evaluator delegates to the definition

These three are about `Reference.evaluateDoc` itself, the function the oracle runs, and not
about a copy of it. They are proved by unfolding it. They say that once the evaluator has built
its environment, the values and the decision are the definition's. They say nothing about
whether that environment is the one the specification describes: acceptance by source,
conformance, conflicts and closed kinds are inside the `∃ env` and remain unproved. -/

/-- The evaluator's decision is the definition's aggregation of its requirement values. -/
theorem evaluateDoc_decision (doc : Doc) (raw : RawEnv) (o : Outcome)
    (h : evaluateDoc doc raw = .ok o) : o.decision = decide (o.requirements.map (·.2)) := by
  unfold evaluateDoc at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  repeat' split at h
  all_goals first
    | (cases h; rfl)
    | cases h

/-- Each requirement's value is `Pred.eval`, in one environment, of its lowered predicate. -/
theorem evaluateDoc_values (doc : Doc) (raw : RawEnv) (o : Outcome)
    (h : evaluateDoc doc raw = .ok o) :
    ∃ env : Env, o.requirements = doc.requires.map (fun r => (r.1, (lower r.2).eval env [])) := by
  unfold evaluateDoc at h
  simp only [bind, Except.bind, pure, Except.pure, List.map_map, Function.comp_def] at h
  repeat' split at h
  all_goals first
    | (cases h; exact ⟨_, rfl⟩)
    | (cases h; done)

/-- So the evaluator's decision is the definition's `evaluate`, in that environment, of the
    lowered requirements. -/
theorem evaluateDoc_is_definition (doc : Doc) (raw : RawEnv) (o : Outcome)
    (h : evaluateDoc doc raw = .ok o) :
    ∃ env : Env, o.decision = evaluate env (doc.requires.map fun r => lower r.2) := by
  obtain ⟨env, hvalues⟩ := evaluateDoc_values doc raw o h
  refine ⟨env, ?_⟩
  rw [evaluateDoc_decision doc raw o h, hvalues]
  simp [evaluate, List.map_map, Function.comp_def]

end Refinement

#print axioms Refinement.and_assoc
#print axioms Refinement.or_assoc
#print axioms Refinement.and_true
#print axioms Refinement.or_false
#print axioms Refinement.foldl_and_eval
#print axioms Refinement.foldl_or_eval
#print axioms Refinement.emptyAnd_eval
#print axioms Refinement.emptyOr_eval
#print axioms Refinement.lowerTotal_eval
#print axioms Refinement.lowerList_eval
#print axioms Refinement.lowerOver_eval
#print axioms Refinement.lowered_decision
#print axioms Refinement.evaluateDoc_decision
#print axioms Refinement.evaluateDoc_values
#print axioms Refinement.evaluateDoc_is_definition

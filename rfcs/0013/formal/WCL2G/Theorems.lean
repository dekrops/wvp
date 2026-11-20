import WCL2G.Semantics
import WCL2T.Theorems

/-!
What is proved about completeness per group: it changes nothing for contracts that don't use it,
and a group closes only what it names. Stability along more evidence is in `Stability.lean`.
-/

namespace WCL2G

open Verified.Contract
open WCL2 (Aggregate Judged definite number)

/-! ## Nothing changes for a contract without `per` -/

/-- An RFC 0011 term or predicate, with no group: every quantifier reads the whole kind. The key
    is a placeholder that is never evaluated for its value. -/
def noKey : Term := .lit .int (.num 0)

mutual
  def Term.ofT : WCL2T.Term → Term
    | .lit ty value => .lit ty value
    | .input name => .input name
    | .param name => .param name
    | .field var name => .field var name
    | .add left right => .add (Term.ofT left) (Term.ofT right)
    | .sub left right => .sub (Term.ofT left) (Term.ofT right)
    | .scale factor arg => .scale factor (Term.ofT arg)
    | .abs arg => .abs (Term.ofT arg)
    | .mul left right => .mul (Term.ofT left) (Term.ofT right)
    | .agg fn var kind body => .agg fn var kind none noKey (Pred.ofT body)

  def Pred.ofT : WCL2T.Pred → Pred
    | .cmp op left right => .cmp op (Term.ofT left) (Term.ofT right)
    | .and left right => .and (Pred.ofT left) (Pred.ofT right)
    | .or left right => .or (Pred.ofT left) (Pred.ofT right)
    | .not arg => .not (Pred.ofT arg)
    | .ex var kind body => .ex var kind none noKey (Pred.ofT body)
    | .all var kind body => .all var kind none noKey (Pred.ofT body)
    | .agg fn var kind body op bound => .agg fn var kind none noKey (Pred.ofT body) op (Term.ofT bound)
end

mutual
  theorem term_ofT_eval (env : GEnv) : (term : WCL2T.Term) → ∀ scope,
      (Term.ofT term).eval env scope = term.eval env.base scope
    | .lit _ _, _ => rfl
    | .input _, _ => rfl
    | .param _, _ => rfl
    | .field _ _, _ => rfl
    | .add left right, scope => by
      simp only [Term.ofT, Term.eval, WCL2T.Term.eval, term_ofT_eval env left, term_ofT_eval env right]
      cases number (WCL2T.Term.eval env.base left scope) <;>
        cases number (WCL2T.Term.eval env.base right scope) <;> rfl
    | .sub left right, scope => by
      simp only [Term.ofT, Term.eval, WCL2T.Term.eval, term_ofT_eval env left, term_ofT_eval env right]
      cases number (WCL2T.Term.eval env.base left scope) <;>
        cases number (WCL2T.Term.eval env.base right scope) <;> rfl
    | .scale _ arg, scope => by
      simp only [Term.ofT, Term.eval, WCL2T.Term.eval, term_ofT_eval env arg]
    | .abs arg, scope => by
      simp only [Term.ofT, Term.eval, WCL2T.Term.eval, term_ofT_eval env arg]
    | .mul left right, scope => by
      simp only [Term.ofT, Term.eval, WCL2T.Term.eval, term_ofT_eval env left, term_ofT_eval env right]
      cases number (WCL2T.Term.eval env.base left scope) <;>
        cases number (WCL2T.Term.eval env.base right scope) <;> rfl
    | .agg fn var kind body, scope => by
      simp only [Term.ofT, Term.eval, WCL2T.Term.eval, listing]
      congr 2
      apply List.map_congr_left
      intro record _
      rw [pred_ofT_eval env body]

  /-- Every RFC 0011 requirement means the same here, whatever groups are declared: a contract
      that doesn't say `per` is decided exactly as before. -/
  theorem pred_ofT_eval (env : GEnv) : (pred : WCL2T.Pred) → ∀ scope,
      (Pred.ofT pred).eval env scope = pred.eval env.base scope
    | .cmp op left right, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, term_ofT_eval env left, term_ofT_eval env right]
      cases WCL2T.Term.eval env.base left scope <;> cases WCL2T.Term.eval env.base right scope <;> rfl
    | .and left right, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, pred_ofT_eval env left, pred_ofT_eval env right]
    | .or left right, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, pred_ofT_eval env left, pred_ofT_eval env right]
    | .not arg, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, pred_ofT_eval env arg]
    | .ex var kind body, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, listing]
      have : ((env.base.records kind).map fun record => (Pred.ofT body).eval env ((var, record) :: scope)) =
          (env.base.records kind).map fun record => body.eval env.base ((var, record) :: scope) :=
        List.map_congr_left fun record _ => pred_ofT_eval env body _
      rw [this]
    | .all var kind body, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, listing]
      have : ((env.base.records kind).map fun record => (Pred.ofT body).eval env ((var, record) :: scope)) =
          (env.base.records kind).map fun record => body.eval env.base ((var, record) :: scope) :=
        List.map_congr_left fun record _ => pred_ofT_eval env body _
      rw [this]
    | .agg fn var kind body op bound, scope => by
      simp only [Pred.ofT, Pred.eval, WCL2T.Pred.eval, listing, term_ofT_eval env bound]
      have : ((env.base.records kind).map fun record =>
            (record, (Pred.ofT body).eval env ((var, record) :: scope))) =
          (env.base.records kind).map fun record => (record, body.eval env.base ((var, record) :: scope)) :=
        List.map_congr_left fun record _ => by rw [pred_ofT_eval env body]
      rw [this]
      cases fn.value (env.base.closed kind)
          ((env.base.records kind).map fun record => (record, body.eval env.base ((var, record) :: scope))) <;>
        cases WCL2T.Term.eval env.base bound scope <;> rfl
end

/-- A contract without `per` has the same decision as under RFC 0011, whatever groups are
    declared complete. -/
theorem same_decision_without_per (env : GEnv) (requirements : List WCL2T.Pred) :
    evaluate env (requirements.map Pred.ofT) = WCL2T.evaluate env.base requirements := by
  simp only [evaluate, WCL2T.evaluate, List.map_map]
  congr 1
  apply List.map_congr_left
  intro pred _
  exact pred_ofT_eval env pred []

/-! ## A group closes only what it names -/

/-- A listing is closed only if its kind is closed, or the quantifier reads one group and a
    source declared exactly that group complete. -/
theorem listing_closed_iff (env : GEnv) (kind : String) (group : Option String) (key : Option Value) :
    (listing env kind group key).1 = true ↔
      (group = none ∧ env.base.closed kind = true) ∨
        (∃ field value, group = some field ∧ key = some value ∧
          (env.base.closed kind = true ∨ env.groups kind field value = true)) := by
  cases group with
  | none => simp [listing]
  | some field =>
    cases key with
    | none => simp [listing]
    | some value => simp [listing]

/-- A group's listing holds the records of the kind with that value in the field, and only
    them. -/
theorem mem_group_listing (env : GEnv) (kind field : String) (value : Value) (record : Record) :
    record ∈ (listing env kind (some field) (some value)).2 ↔
      record ∈ env.base.records kind ∧ record.get field = some value := by
  simp [listing]

/-- Fail closed: an `exists` over a group is `FALSE` only if the kind, or that very group, was
    declared complete. Missing evidence never becomes `FALSE`. -/
theorem ex_false_requires_closed_group (env : GEnv) (var kind field : String) (key : Term)
    (body : Pred) (scope : Scope) (h : (Pred.ex var kind (some field) key body).eval env scope = .false) :
    ∃ value, key.eval env scope = some value ∧
      (env.base.closed kind = true ∨ env.groups kind field value = true) := by
  simp only [Pred.eval] at h
  cases hk : key.eval env scope with
  | none =>
    rw [hk] at h
    simp [listing, Truth.any] at h
  | some value =>
    rw [hk] at h
    refine ⟨value, rfl, ?_⟩
    cases hc : (env.base.closed kind || env.groups kind field value) with
    | true => simpa using hc
    | false =>
      simp only [listing, hc] at h
      split at h
      · contradiction
      · rename_i guard
        exact absurd ⟨h, trivial⟩ guard

/-- The same for a `forall` that is `TRUE`. -/
theorem all_true_requires_closed_group (env : GEnv) (var kind field : String) (key : Term)
    (body : Pred) (scope : Scope) (h : (Pred.all var kind (some field) key body).eval env scope = .true) :
    ∃ value, key.eval env scope = some value ∧
      (env.base.closed kind = true ∨ env.groups kind field value = true) := by
  simp only [Pred.eval] at h
  cases hk : key.eval env scope with
  | none =>
    rw [hk] at h
    simp [listing, Truth.all] at h
  | some value =>
    rw [hk] at h
    refine ⟨value, rfl, ?_⟩
    cases hc : (env.base.closed kind || env.groups kind field value) with
    | true => simpa using hc
    | false =>
      simp only [listing, hc] at h
      split at h
      · contradiction
      · rename_i guard
        exact absurd ⟨h, trivial⟩ guard

/-- An aggregate over a group has a value only if the kind or that group was declared
    complete. -/
theorem agg_value_requires_closed_group (env : GEnv) (fn : Aggregate) (var kind field : String)
    (key : Term) (body : Pred) (scope : Scope) (v : Value)
    (h : (Term.agg fn var kind (some field) key body).eval env scope = some v) :
    ∃ value, key.eval env scope = some value ∧
      (env.base.closed kind = true ∨ env.groups kind field value = true) := by
  simp only [Term.eval] at h
  cases hk : key.eval env scope with
  | none =>
    rw [hk] at h
    simp [listing, Aggregate.value] at h
  | some value =>
    rw [hk] at h
    refine ⟨value, rfl, ?_⟩
    cases hv : fn.value (listing env kind (some field) (some value)).1
        ((listing env kind (some field) (some value)).2.map
          fun record => (record, body.eval env ((var, record) :: scope))) with
    | none => rw [hv] at h; contradiction
    | some n =>
      have closed := (WCL2.aggregate_value_requires_closed fn _ _ n hv).1
      simpa [listing] using closed

end WCL2G

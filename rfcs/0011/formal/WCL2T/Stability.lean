import WCL2T.Semantics
import WCL2.Theorems

/-!
Stability along a settled extension, for aggregates as terms.

RFC 0008 proves that a `TRUE` or `FALSE` requirement stays so when more evidence arrives
(`eval_monotone`, `definite_decision_is_stable`). Its argument rests on terms not depending on the
evidence at all. Here a term can be an aggregate, so a term can gain a value later. The statement
for terms is therefore one-sided: **a term that has a value keeps it**. Requirements are as in
RFC 0008: only `unknown` can change.

Each kind of node is one lemma below, stated over plain values; the mutual proof at the end only
plugs the induction hypotheses into them.
-/

namespace WCL2T

open Verified.Contract
open WCL2 (Aggregate Judged definite number Settled)

/-! ## The evaluation, one node at a time -/

/-- A comparison of two values that may be missing. -/
def cmpOpt (op : Op) : Option Value → Option Value → Truth
  | some a, some b => compare op a b
  | _, _ => .unknown

/-- Arithmetic on two values that may be missing or not numbers. -/
def arith (f : Int → Int → Int) (x y : Option Value) : Option Value :=
  match number x, number y with
  | some a, some b => some (.num (f a b))
  | _, _ => none

/-- An existential's value from its bodies' values, as `Pred.eval` takes it. -/
def exVal (closed : Bool) (values : List Truth) : Truth :=
  if Truth.any values = .false ∧ closed = false then .unknown else Truth.any values

/-- A universal's value from its bodies' values, as `Pred.eval` takes it. -/
def allVal (closed : Bool) (values : List Truth) : Truth :=
  if Truth.all values = .true ∧ closed = false then .unknown else Truth.all values

/-- An aggregate term's value. -/
def aggVal (env : Env) (fn : Aggregate) (kind : String) (body : Record → Truth) : Option Value :=
  (fn.value (env.closed kind) ((env.records kind).map fun record => (record, body record))).map .num

theorem eval_add (env : Env) (left right : Term) (scope : Scope) :
    (Term.add left right).eval env scope = arith (· + ·) (left.eval env scope) (right.eval env scope) := by
  simp only [Term.eval, arith]
  cases number (left.eval env scope) <;> cases number (right.eval env scope) <;> rfl

theorem eval_sub (env : Env) (left right : Term) (scope : Scope) :
    (Term.sub left right).eval env scope = arith (· - ·) (left.eval env scope) (right.eval env scope) := by
  simp only [Term.eval, arith]
  cases number (left.eval env scope) <;> cases number (right.eval env scope) <;> rfl

theorem eval_mul (env : Env) (left right : Term) (scope : Scope) :
    (Term.mul left right).eval env scope = arith (· * ·) (left.eval env scope) (right.eval env scope) := by
  simp only [Term.eval, arith]
  cases number (left.eval env scope) <;> cases number (right.eval env scope) <;> rfl

theorem eval_aggTerm (env : Env) (fn : Aggregate) (var kind : String) (body : Pred) (scope : Scope) :
    (Term.agg fn var kind body).eval env scope =
      aggVal env fn kind fun record => body.eval env ((var, record) :: scope) := by
  simp only [Term.eval, aggVal]

theorem eval_cmp (env : Env) (op : Op) (left right : Term) (scope : Scope) :
    (Pred.cmp op left right).eval env scope = cmpOpt op (left.eval env scope) (right.eval env scope) := by
  simp only [Pred.eval]
  cases left.eval env scope <;> cases right.eval env scope <;> rfl

theorem eval_ex (env : Env) (var kind : String) (body : Pred) (scope : Scope) :
    (Pred.ex var kind body).eval env scope =
      exVal (env.closed kind) ((env.records kind).map fun record => body.eval env ((var, record) :: scope)) := by
  simp only [Pred.eval, exVal]

theorem eval_all (env : Env) (var kind : String) (body : Pred) (scope : Scope) :
    (Pred.all var kind body).eval env scope =
      allVal (env.closed kind) ((env.records kind).map fun record => body.eval env ((var, record) :: scope)) := by
  simp only [Pred.eval, allVal]

theorem eval_aggPred (env : Env) (fn : Aggregate) (var kind : String) (body : Pred) (op : Op)
    (bound : Term) (scope : Scope) :
    (Pred.agg fn var kind body op bound).eval env scope =
      cmpOpt op (aggVal env fn kind fun record => body.eval env ((var, record) :: scope))
        (bound.eval env scope) := by
  simp only [Pred.eval, aggVal]
  cases fn.value (env.closed kind) _ <;> cases bound.eval env scope <;> rfl

/-! ## Each node keeps what is settled -/

/-- A value, once there, is kept. -/
def Kept (x y : Option Value) : Prop := ∀ v, x = some v → y = some v

/-- A `TRUE` or `FALSE`, once there, is kept. -/
def KeptTruth (a b : Truth) : Prop := (a = .true → b = .true) ∧ (a = .false → b = .false)

theorem number_kept {x y : Option Value} (kept : Kept x y) {a : Int} (h : number x = some a) :
    number y = some a := by
  cases x with
  | none => simp [number] at h
  | some v => rw [kept v rfl]; exact h

theorem arith_kept (f : Int → Int → Int) {x y x' y' : Option Value} (kx : Kept x y) (ky : Kept x' y') :
    Kept (arith f x x') (arith f y y') := by
  intro v h
  unfold arith at h ⊢
  revert h
  cases ha : number x with
  | none => simp
  | some a =>
    cases hb : number x' with
    | none => simp
    | some b =>
      intro h
      rw [number_kept kx ha, number_kept ky hb]
      exact h

theorem map_kept (g : Int → Value) {x y : Option Value} (kept : Kept x y) :
    Kept ((number x).map g) ((number y).map g) := by
  intro v
  cases ha : number x with
  | none => simp
  | some a =>
    intro h
    rw [number_kept kept ha]
    exact h

theorem cmpOpt_kept (op : Op) {x y x' y' : Option Value} (kx : Kept x y) (ky : Kept x' y') :
    KeptTruth (cmpOpt op x x') (cmpOpt op y y') := by
  cases x with
  | none => exact ⟨fun h => by simp [cmpOpt] at h, fun h => by simp [cmpOpt] at h⟩
  | some a =>
    cases x' with
    | none => exact ⟨fun h => by simp [cmpOpt] at h, fun h => by simp [cmpOpt] at h⟩
    | some b =>
      rw [kx a rfl, ky b rfl]
      exact ⟨id, id⟩

theorem exVal_kept {earlier later : Env} (ext : Extends earlier later) (kind : String)
    (f g : Record → Truth) (keep : ∀ record, KeptTruth (f record) (g record)) :
    KeptTruth (exVal (earlier.closed kind) ((earlier.records kind).map f))
      (exVal (later.closed kind) ((later.records kind).map g)) := by
  constructor
  · intro h
    unfold exVal at h ⊢
    split at h
    · contradiction
    · obtain ⟨record, member, value⟩ := List.mem_map.mp (any_eq_true.mp h)
      have seen : Truth.any ((later.records kind).map g) = .true :=
        any_eq_true.mpr (List.mem_map.mpr ⟨record, ext.records kind record member, (keep record).1 value⟩)
      split
      · rename_i guard
        rw [seen] at guard
        exact absurd guard.1 (by decide)
      · exact seen
  · intro h
    unfold exVal at h ⊢
    split at h
    · contradiction
    · rename_i guard
      have allFalse := any_eq_false.mp h
      have closed : earlier.closed kind = true := by
        cases c : earlier.closed kind with
        | true => rfl
        | false => exact absurd ⟨h, c⟩ guard
      obtain ⟨stillClosed, nothingNew⟩ := ext.closed kind closed
      have seen : Truth.any ((later.records kind).map g) = .false := by
        apply any_eq_false.mpr
        intro value member
        obtain ⟨record, inLater, rfl⟩ := List.mem_map.mp member
        exact (keep record).2 (allFalse _ (List.mem_map.mpr ⟨record, nothingNew record inLater, rfl⟩))
      split
      · rename_i guard'
        rw [stillClosed] at guard'
        exact absurd guard'.2 (by decide)
      · exact seen

theorem allVal_kept {earlier later : Env} (ext : Extends earlier later) (kind : String)
    (f g : Record → Truth) (keep : ∀ record, KeptTruth (f record) (g record)) :
    KeptTruth (allVal (earlier.closed kind) ((earlier.records kind).map f))
      (allVal (later.closed kind) ((later.records kind).map g)) := by
  constructor
  · intro h
    unfold allVal at h ⊢
    split at h
    · contradiction
    · rename_i guard
      have allTrue := all_eq_true.mp h
      have closed : earlier.closed kind = true := by
        cases c : earlier.closed kind with
        | true => rfl
        | false => exact absurd ⟨h, c⟩ guard
      obtain ⟨stillClosed, nothingNew⟩ := ext.closed kind closed
      have seen : Truth.all ((later.records kind).map g) = .true := by
        apply all_eq_true.mpr
        intro value member
        obtain ⟨record, inLater, rfl⟩ := List.mem_map.mp member
        exact (keep record).1 (allTrue _ (List.mem_map.mpr ⟨record, nothingNew record inLater, rfl⟩))
      split
      · rename_i guard'
        rw [stillClosed] at guard'
        exact absurd guard'.2 (by decide)
      · exact seen
  · intro h
    unfold allVal at h ⊢
    split at h
    · contradiction
    · obtain ⟨record, member, value⟩ := List.mem_map.mp (all_eq_false.mp h)
      have seen : Truth.all ((later.records kind).map g) = .false :=
        all_eq_false.mpr (List.mem_map.mpr ⟨record, ext.records kind record member, (keep record).2 value⟩)
      split
      · rename_i guard
        rw [seen] at guard
        exact absurd guard.1 (by decide)
      · exact seen

/-- An aggregate with a value keeps it: it was taken over a closed kind with every body settled,
    the later environment lists that kind with the same records, and each body stays settled. -/
theorem aggVal_kept {earlier later : Env} (settled : Settled earlier later) (fn : Aggregate)
    (kind : String) (f g : Record → Truth) (keep : ∀ record, KeptTruth (f record) (g record)) :
    Kept (aggVal earlier fn kind f) (aggVal later fn kind g) := by
  intro v
  unfold aggVal
  cases h : fn.value (earlier.closed kind) ((earlier.records kind).map fun record => (record, f record)) with
  | none => simp
  | some n =>
    intro hv
    obtain ⟨closed, bodiesSettled⟩ := WCL2.aggregate_value_requires_closed fn _ _ n h
    have stillClosed := (settled.ext.closed kind closed).1
    have reordered := WCL2.closed_listing_is_reordered settled kind closed
    have judged := WCL2.settled_bodies_kept (earlier.records kind) (later.records kind) reordered
      f g (fun record => keep record) bodiesSettled
    rw [stillClosed, WCL2.value_perm fn true judged, ← closed, h]
    exact hv

/-! ## Stability -/

mutual
  /-- A term with a value keeps it along a settled extension. An aggregate term may gain a value
      later; it never loses or changes one. -/
  theorem term_kept {earlier later : Env} (settled : Settled earlier later) :
      (term : Term) → ∀ scope, Kept (term.eval earlier scope) (term.eval later scope)
    | .lit _ _, _ => fun _ h => h
    | .input _, _ => fun v h => by simp only [Term.eval] at h ⊢; rw [settled.ext.inputs]; exact h
    | .param _, _ => fun v h => by simp only [Term.eval] at h ⊢; rw [settled.ext.params]; exact h
    | .field _ _, _ => fun v h => by simp only [Term.eval] at h ⊢; exact h
    | .add left right, scope => by
      rw [eval_add, eval_add]
      exact arith_kept _ (term_kept settled left scope) (term_kept settled right scope)
    | .sub left right, scope => by
      rw [eval_sub, eval_sub]
      exact arith_kept _ (term_kept settled left scope) (term_kept settled right scope)
    | .mul left right, scope => by
      rw [eval_mul, eval_mul]
      exact arith_kept _ (term_kept settled left scope) (term_kept settled right scope)
    | .scale factor arg, scope => by
      simp only [Term.eval]
      exact map_kept _ (term_kept settled arg scope)
    | .abs arg, scope => by
      simp only [Term.eval]
      exact map_kept _ (term_kept settled arg scope)
    | .agg fn var kind body, scope => by
      rw [eval_aggTerm, eval_aggTerm]
      exact aggVal_kept settled fn kind _ _ fun record => pred_kept settled body ((var, record) :: scope)

  /-- Monotonicity along `Settled`, aggregate terms included: a requirement that is true stays
      true and one that is false stays false. Only `unknown` can change. -/
  theorem pred_kept {earlier later : Env} (settled : Settled earlier later) :
      (pred : Pred) → ∀ scope, KeptTruth (pred.eval earlier scope) (pred.eval later scope)
    | .cmp op left right, scope => by
      rw [eval_cmp, eval_cmp]
      exact cmpOpt_kept op (term_kept settled left scope) (term_kept settled right scope)
    | .and left right, scope => by
      have l := pred_kept settled left scope
      have r := pred_kept settled right scope
      simp only [Pred.eval]
      constructor
      · intro h
        have ⟨hl, hr⟩ := and_eq_true.mp h
        exact and_eq_true.mpr ⟨l.1 hl, r.1 hr⟩
      · intro h
        rcases and_eq_false.mp h with hl | hr
        · exact and_eq_false.mpr (Or.inl (l.2 hl))
        · exact and_eq_false.mpr (Or.inr (r.2 hr))
    | .or left right, scope => by
      have l := pred_kept settled left scope
      have r := pred_kept settled right scope
      simp only [Pred.eval]
      constructor
      · intro h
        rcases or_eq_true.mp h with hl | hr
        · exact or_eq_true.mpr (Or.inl (l.1 hl))
        · exact or_eq_true.mpr (Or.inr (r.1 hr))
      · intro h
        have ⟨hl, hr⟩ := or_eq_false.mp h
        exact or_eq_false.mpr ⟨l.2 hl, r.2 hr⟩
    | .not arg, scope => by
      have a := pred_kept settled arg scope
      simp only [Pred.eval]
      exact ⟨fun h => not_eq_true.mpr (a.2 (not_eq_true.mp h)),
        fun h => not_eq_false.mpr (a.1 (not_eq_false.mp h))⟩
    | .ex var kind body, scope => by
      rw [eval_ex, eval_ex]
      exact exVal_kept settled.ext kind _ _ fun record => pred_kept settled body ((var, record) :: scope)
    | .all var kind body, scope => by
      rw [eval_all, eval_all]
      exact allVal_kept settled.ext kind _ _ fun record => pred_kept settled body ((var, record) :: scope)
    | .agg fn var kind body op bound, scope => by
      rw [eval_aggPred, eval_aggPred]
      exact cmpOpt_kept op
        (aggVal_kept settled fn kind _ _ fun record => pred_kept settled body ((var, record) :: scope))
        (term_kept settled bound scope)
end

/-- RFC 0008's `eval_monotone`, for aggregates as terms. -/
theorem eval_monotone {earlier later : Env} (settled : Settled earlier later) (pred : Pred) :
    ∀ scope : Scope,
      (pred.eval earlier scope = .true → pred.eval later scope = .true) ∧
        (pred.eval earlier scope = .false → pred.eval later scope = .false) :=
  pred_kept settled pred

/-- Between an environment and a settled extension of it, a supported decision stays supported
    and a contradicted one stays contradicted, aggregate terms and products included. -/
theorem definite_decision_is_stable {earlier later : Env} (settled : Settled earlier later)
    (requirements : List Pred) :
    (evaluate earlier requirements = .supported → evaluate later requirements = .supported) ∧
      (evaluate earlier requirements = .contradicted →
        evaluate later requirements = .contradicted) := by
  unfold evaluate
  constructor
  · intro h
    apply (supported_iff_all_true _).mpr
    intro value member
    obtain ⟨requirement, inRequirements, rfl⟩ := List.mem_map.mp member
    exact (eval_monotone settled requirement []).1
      ((supported_iff_all_true _).mp h _ (List.mem_map.mpr ⟨requirement, inRequirements, rfl⟩))
  · intro h
    apply (contradicted_iff_some_false _).mpr
    obtain ⟨requirement, inRequirements, value⟩ :=
      List.mem_map.mp ((contradicted_iff_some_false _).mp h)
    exact List.mem_map.mpr ⟨requirement, inRequirements, (eval_monotone settled requirement []).2 value⟩

end WCL2T

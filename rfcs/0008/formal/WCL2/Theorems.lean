import WCL2.Semantics

/-!
What is proved about Work Contract Language 2 as `Semantics.lean` defines it.

These are theorems about the model, like formal/lean's about Language 1. They are not theorems
about any implementation, the wire form or the typing.
-/

namespace WCL2

open Verified.Contract

/-! ## Language 2 extends Language 1 -/

def Term.ofV1 : Verified.Contract.Term → Term
  | .lit ty value => .lit ty value
  | .input name => .input name
  | .param name => .param name
  | .field var name => .field var name

def Pred.ofV1 : Verified.Contract.Pred → Pred
  | .cmp op left right => .cmp op (Term.ofV1 left) (Term.ofV1 right)
  | .and left right => .and (Pred.ofV1 left) (Pred.ofV1 right)
  | .or left right => .or (Pred.ofV1 left) (Pred.ofV1 right)
  | .not arg => .not (Pred.ofV1 arg)
  | .ex var kind body => .ex var kind (Pred.ofV1 body)
  | .all var kind body => .all var kind (Pred.ofV1 body)

theorem term_ofV1_eval (env : Env) (scope : Scope) (term : Verified.Contract.Term) :
    (Term.ofV1 term).eval env scope = term.eval env scope := by
  cases term <;> rfl

/-- Every Language 1 requirement means the same in Language 2: the same value in every
    environment. Nothing a Language 1 contract decides is decided differently. -/
theorem extends_language_1 (env : Env) (pred : Verified.Contract.Pred) :
    ∀ scope, (Pred.ofV1 pred).eval env scope = pred.eval env scope := by
  induction pred with
  | cmp op left right =>
    intro scope
    simp only [Pred.ofV1, Pred.eval, Verified.Contract.Pred.eval, term_ofV1_eval]
    cases Verified.Contract.Term.eval env scope left <;>
      cases Verified.Contract.Term.eval env scope right <;> rfl
  | and left right ihl ihr =>
    intro scope
    simp only [Pred.ofV1, Pred.eval, Verified.Contract.Pred.eval, ihl, ihr]
  | or left right ihl ihr =>
    intro scope
    simp only [Pred.ofV1, Pred.eval, Verified.Contract.Pred.eval, ihl, ihr]
  | not arg ih =>
    intro scope
    simp only [Pred.ofV1, Pred.eval, Verified.Contract.Pred.eval, ih]
  | ex var kind body ih =>
    intro scope
    simp only [Pred.ofV1, Pred.eval, Verified.Contract.Pred.eval, ih]
  | all var kind body ih =>
    intro scope
    simp only [Pred.ofV1, Pred.eval, Verified.Contract.Pred.eval, ih]

/-- A Language 1 contract has the same decision under Language 2. -/
theorem same_decision_as_language_1 (env : Env) (requirements : List Verified.Contract.Pred) :
    evaluate env (requirements.map Pred.ofV1) = Verified.Contract.evaluate env requirements := by
  simp only [evaluate, Verified.Contract.evaluate, List.map_map]
  congr 1
  apply List.map_congr_left
  intro pred _
  exact extends_language_1 env pred []

/-! ## Aggregates count only complete listings -/

/-- An aggregate with a value was taken over a closed kind, every body settled. -/
theorem aggregate_value_requires_closed (fn : Aggregate) (closed : Bool) (judged : Judged)
    (n : Int) (h : fn.value closed judged = some n) : closed = true ∧ definite judged = true := by
  unfold Aggregate.value at h
  split at h
  · rename_i guard
    exact guard
  · contradiction

/-- A comparison with an aggregate is settled only over a closed kind. -/
theorem aggregate_settled_requires_closed (env : Env) (fn : Aggregate) (var kind : String)
    (body : Pred) (op : Op) (bound : Term) (scope : Scope)
    (h : (Pred.agg fn var kind body op bound).eval env scope ≠ .unknown) :
    env.closed kind = true ∧
      ∀ record ∈ env.records kind, body.eval env ((var, record) :: scope) ≠ .unknown := by
  simp only [Pred.eval] at h
  split at h
  · rename_i n b hv _
    obtain ⟨closed, settled⟩ := aggregate_value_requires_closed fn _ _ n hv
    refine ⟨closed, fun record member => ?_⟩
    have := List.all_eq_true.mp settled (record, body.eval env ((var, record) :: scope))
      (List.mem_map.mpr ⟨record, member, rfl⟩)
    simpa using this
  · contradiction

/-- Fail closed: over a kind no source declared complete, every aggregate comparison is
    unknown, however many records were seen. -/
theorem aggregate_open_kind_is_unknown (env : Env) (fn : Aggregate) (var kind : String)
    (body : Pred) (op : Op) (bound : Term) (scope : Scope) (open_ : env.closed kind = false) :
    (Pred.agg fn var kind body op bound).eval env scope = .unknown := by
  cases h : (Pred.agg fn var kind body op bound).eval env scope with
  | unknown => rfl
  | true =>
    have := (aggregate_settled_requires_closed env fn var kind body op bound scope
      (by rw [h]; decide)).1
    rw [open_] at this
    contradiction
  | false =>
    have := (aggregate_settled_requires_closed env fn var kind body op bound scope
      (by rw [h]; decide)).1
    rw [open_] at this
    contradiction

/-! ## Quantifiers, as in Language 1 -/

theorem exists_true_has_witness (env : Env) (var kind : String) (body : Pred) (scope : Scope)
    (h : (Pred.ex var kind body).eval env scope = .true) :
    ∃ record ∈ env.records kind, body.eval env ((var, record) :: scope) = .true := by
  simp only [Pred.eval] at h
  split at h
  · contradiction
  · obtain ⟨record, inRecords, value⟩ := List.mem_map.mp (any_eq_true.mp h)
    exact ⟨record, inRecords, value⟩

theorem exists_false_requires_closed (env : Env) (var kind : String) (body : Pred) (scope : Scope)
    (h : (Pred.ex var kind body).eval env scope = .false) :
    env.closed kind = true ∧
      ∀ record ∈ env.records kind, body.eval env ((var, record) :: scope) = .false := by
  simp only [Pred.eval] at h
  split at h
  · contradiction
  · rename_i guard
    have allFalse := any_eq_false.mp h
    refine ⟨?_, fun record member => allFalse _ (List.mem_map.mpr ⟨record, member, rfl⟩)⟩
    cases closed : env.closed kind with
    | true => rfl
    | false => exact absurd ⟨h, closed⟩ guard

theorem forall_true_requires_closed (env : Env) (var kind : String) (body : Pred) (scope : Scope)
    (h : (Pred.all var kind body).eval env scope = .true) :
    env.closed kind = true ∧
      ∀ record ∈ env.records kind, body.eval env ((var, record) :: scope) = .true := by
  simp only [Pred.eval] at h
  split at h
  · contradiction
  · rename_i guard
    have allTrue := all_eq_true.mp h
    refine ⟨?_, fun record member => allTrue _ (List.mem_map.mpr ⟨record, member, rfl⟩)⟩
    cases closed : env.closed kind with
    | true => rfl
    | false => exact absurd ⟨h, closed⟩ guard

theorem forall_false_has_counterexample (env : Env) (var kind : String) (body : Pred)
    (scope : Scope) (h : (Pred.all var kind body).eval env scope = .false) :
    ∃ record ∈ env.records kind, body.eval env ((var, record) :: scope) = .false := by
  simp only [Pred.eval] at h
  split at h
  · contradiction
  · obtain ⟨record, inRecords, value⟩ := List.mem_map.mp (all_eq_false.mp h)
    exact ⟨record, inRecords, value⟩

/-! ## Stability along a settled extension -/

/-- `Extends`, as Language 1 states it, and in addition: a closed kind is listed as it was.
    Language 1's `Extends` already says a closed kind keeps exactly its records; an aggregate
    also needs the listing itself unchanged, which holds when records are distinct by key and
    listed in key order. RFC 0008 asks for that to be proved rather than assumed. -/
structure Settled (earlier later : Env) : Prop where
  ext : Extends earlier later
  listed : ∀ kind, earlier.closed kind = true → later.records kind = earlier.records kind

theorem term_eval_extends {earlier later : Env} (ext : Extends earlier later) (scope : Scope)
    (term : Term) : term.eval later scope = term.eval earlier scope := by
  induction term with
  | lit => rfl
  | input => simp [Term.eval, ext.inputs]
  | param => simp [Term.eval, ext.params]
  | field => rfl
  | add left right ihl ihr => simp only [Term.eval, ihl, ihr]
  | sub left right ihl ihr => simp only [Term.eval, ihl, ihr]
  | scale factor arg ih => simp only [Term.eval, ih]
  | abs arg ih => simp only [Term.eval, ih]

/-- A settled truth value is kept, for each record of a listing whose bodies were all settled. -/
theorem settled_bodies_kept (records : List Record)
    (body : Record → Truth) (body' : Record → Truth)
    (keep : ∀ record, (body record = .true → body' record = .true) ∧
      (body record = .false → body' record = .false))
    (settled : definite (records.map fun record => (record, body record)) = true) :
    (records.map fun record => (record, body' record)) =
      (records.map fun record => (record, body record)) := by
  apply List.map_congr_left
  intro record member
  have hs := List.all_eq_true.mp settled (record, body record)
    (List.mem_map.mpr ⟨record, member, rfl⟩)
  simp only [decide_eq_true_eq] at hs
  cases hb : body record with
  | true => rw [(keep record).1 hb]
  | false => rw [(keep record).2 hb]
  | unknown => exact absurd hb hs

/-- Monotonicity along `Settled`: a requirement that is true stays true and one that is false
    stays false, aggregates included. Only `unknown` can change. -/
theorem eval_monotone {earlier later : Env} (settled : Settled earlier later) (pred : Pred) :
    ∀ scope : Scope,
      (pred.eval earlier scope = .true → pred.eval later scope = .true) ∧
        (pred.eval earlier scope = .false → pred.eval later scope = .false) := by
  have ext := settled.ext
  induction pred with
  | cmp op left right =>
    intro scope
    simp only [Pred.eval, term_eval_extends ext]
    exact ⟨id, id⟩
  | and left right ihl ihr =>
    intro scope
    simp only [Pred.eval]
    constructor
    · intro h
      have ⟨l, r⟩ := and_eq_true.mp h
      exact and_eq_true.mpr ⟨(ihl scope).1 l, (ihr scope).1 r⟩
    · intro h
      rcases and_eq_false.mp h with l | r
      · exact and_eq_false.mpr (Or.inl ((ihl scope).2 l))
      · exact and_eq_false.mpr (Or.inr ((ihr scope).2 r))
  | or left right ihl ihr =>
    intro scope
    simp only [Pred.eval]
    constructor
    · intro h
      rcases or_eq_true.mp h with l | r
      · exact or_eq_true.mpr (Or.inl ((ihl scope).1 l))
      · exact or_eq_true.mpr (Or.inr ((ihr scope).1 r))
    · intro h
      have ⟨l, r⟩ := or_eq_false.mp h
      exact or_eq_false.mpr ⟨(ihl scope).2 l, (ihr scope).2 r⟩
  | not arg ih =>
    intro scope
    simp only [Pred.eval]
    exact ⟨fun h => not_eq_true.mpr ((ih scope).2 (not_eq_true.mp h)),
      fun h => not_eq_false.mpr ((ih scope).1 (not_eq_false.mp h))⟩
  | ex var kind body ih =>
    intro scope
    constructor
    · intro h
      obtain ⟨record, member, value⟩ := exists_true_has_witness earlier var kind body scope h
      have witness : Truth.true ∈
          (later.records kind).map fun record => body.eval later ((var, record) :: scope) :=
        List.mem_map.mpr ⟨record, ext.records kind record member, (ih _).1 value⟩
      have seen := any_eq_true.mpr witness
      simp only [Pred.eval]
      split
      · rename_i guard
        rw [seen] at guard
        exact absurd guard.1 (by decide)
      · exact seen
    · intro h
      obtain ⟨closed, allFalse⟩ := exists_false_requires_closed earlier var kind body scope h
      obtain ⟨stillClosed, nothingNew⟩ := ext.closed kind closed
      have seen : Truth.any
          ((later.records kind).map fun record => body.eval later ((var, record) :: scope)) =
            .false := by
        apply any_eq_false.mpr
        intro value member
        obtain ⟨record, inLater, rfl⟩ := List.mem_map.mp member
        exact (ih _).2 (allFalse record (nothingNew record inLater))
      simp only [Pred.eval]
      split
      · rename_i guard
        rw [stillClosed] at guard
        exact absurd guard.2 (by decide)
      · exact seen
  | all var kind body ih =>
    intro scope
    constructor
    · intro h
      obtain ⟨closed, allTrue⟩ := forall_true_requires_closed earlier var kind body scope h
      obtain ⟨stillClosed, nothingNew⟩ := ext.closed kind closed
      have seen : Truth.all
          ((later.records kind).map fun record => body.eval later ((var, record) :: scope)) =
            .true := by
        apply all_eq_true.mpr
        intro value member
        obtain ⟨record, inLater, rfl⟩ := List.mem_map.mp member
        exact (ih _).1 (allTrue record (nothingNew record inLater))
      simp only [Pred.eval]
      split
      · rename_i guard
        rw [stillClosed] at guard
        exact absurd guard.2 (by decide)
      · exact seen
    · intro h
      obtain ⟨record, member, value⟩ := forall_false_has_counterexample earlier var kind body scope h
      have counterexample : Truth.false ∈
          (later.records kind).map fun record => body.eval later ((var, record) :: scope) :=
        List.mem_map.mpr ⟨record, ext.records kind record member, (ih _).2 value⟩
      have seen := all_eq_false.mpr counterexample
      simp only [Pred.eval]
      split
      · rename_i guard
        rw [seen] at guard
        exact absurd guard.1 (by decide)
      · exact seen
  | agg fn var kind body op bound ih =>
    intro scope
    -- A settled comparison had a value over a closed kind with every body settled. The later
    -- environment lists that kind as it was, and each settled body stays settled, so the
    -- aggregate, the bound and the comparison are the same.
    have same : ∀ v : Truth, v ≠ .unknown →
        (Pred.agg fn var kind body op bound).eval earlier scope = v →
        (Pred.agg fn var kind body op bound).eval later scope = v := by
      intro v hv h
      obtain ⟨closed, _⟩ := aggregate_settled_requires_closed earlier fn var kind body op bound
        scope (by rw [h]; exact hv)
      have stillClosed := (ext.closed kind closed).1
      have listed := settled.listed kind closed
      have bodiesSettled : definite ((earlier.records kind).map fun record =>
          (record, body.eval earlier ((var, record) :: scope))) = true := by
        simp only [Pred.eval] at h
        split at h
        · rename_i n b hval _
          exact (aggregate_value_requires_closed fn _ _ n hval).2
        · exact absurd h.symm hv
      have judged := settled_bodies_kept (earlier.records kind)
        (fun record => body.eval earlier ((var, record) :: scope))
        (fun record => body.eval later ((var, record) :: scope))
        (fun record => ih ((var, record) :: scope)) bodiesSettled
      simp only [Pred.eval] at h ⊢
      rw [stillClosed, listed, judged, term_eval_extends ext, ← closed]
      exact h
    exact ⟨same .true (by decide), same .false (by decide)⟩

/-- Between an environment and a settled extension of it, a supported decision stays supported
    and a contradicted one stays contradicted, aggregates included. -/
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

end WCL2

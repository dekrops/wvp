import Verified.Contract.Semantics

namespace Verified.Contract

/-!
What is proved about the evaluation defined in `Semantics.lean`.

These are theorems about the model. They are not theorems about the Scala evaluator, the JSON
reader, acceptance by source, or conflict resolution; see formal/lean/README.md for what
connects the model to the implementation and what does not.
-/

/-! ## The decision -/

/-- A claim is supported only when every requirement was established. -/
theorem supported_iff_all_true (values : List Truth) :
    decide values = .supported ↔ ∀ value ∈ values, value = .true := by
  unfold decide
  constructor
  · intro h value member
    by_cases hf : Truth.false ∈ values
    · simp [hf] at h
    · by_cases hu : Truth.unknown ∈ values
      · simp [hf, hu] at h
      · cases value with
        | true => rfl
        | false => exact absurd member hf
        | unknown => exact absurd member hu
  · intro h
    have hf : Truth.false ∉ values := fun member => by
      have := h _ member
      contradiction
    have hu : Truth.unknown ∉ values := fun member => by
      have := h _ member
      contradiction
    simp [hf, hu]

/-- A claim is contradicted exactly when some requirement is conclusively false. -/
theorem contradicted_iff_some_false (values : List Truth) :
    decide values = .contradicted ↔ Truth.false ∈ values := by
  unfold decide
  by_cases hf : Truth.false ∈ values
  · simp [hf]
  · by_cases hu : Truth.unknown ∈ values <;> simp [hf, hu]

/-- One unknown requirement is enough to prevent support: missing evidence is never rounded up. -/
theorem unknown_requirement_prevents_support (values : List Truth)
    (member : Truth.unknown ∈ values) : decide values ≠ .supported := by
  intro h
  have := (supported_iff_all_true values).mp h _ member
  contradiction

/-! ## Quantifiers: witnesses, counterexamples and completeness -/

/-- An existential that holds has a witness among the admitted records. Nothing is established
    by absence, by default or by the shape of the contract. -/
theorem exists_true_has_witness (env : Env) (var kind : String) (body : Pred) (scope : Scope)
    (h : (Pred.ex var kind body).eval env scope = .true) :
    ∃ record ∈ env.records kind, body.eval env ((var, record) :: scope) = .true := by
  simp only [Pred.eval] at h
  split at h
  · contradiction
  · have member := any_eq_true.mp h
    obtain ⟨record, inRecords, value⟩ := List.mem_map.mp member
    exact ⟨record, inRecords, value⟩

/-- "There is none" is concluded only from a listing declared complete. -/
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

/-- "All of them" is concluded only from a listing declared complete. -/
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

/-- A universal that fails has a counterexample among the admitted records. -/
theorem forall_false_has_counterexample (env : Env) (var kind : String) (body : Pred)
    (scope : Scope) (h : (Pred.all var kind body).eval env scope = .false) :
    ∃ record ∈ env.records kind, body.eval env ((var, record) :: scope) = .false := by
  simp only [Pred.eval] at h
  split at h
  · contradiction
  · have member := all_eq_false.mp h
    obtain ⟨record, inRecords, value⟩ := List.mem_map.mp member
    exact ⟨record, inRecords, value⟩

/-- Fail closed: over a kind no source declared complete, with no records at all, an existential
    is unknown, and so is a universal. Neither becomes true or false by default. -/
theorem no_records_open_kind_is_unknown (env : Env) (var kind : String) (body : Pred)
    (scope : Scope) (none : env.records kind = []) (open_ : env.closed kind = false) :
    (Pred.ex var kind body).eval env scope = .unknown ∧
      (Pred.all var kind body).eval env scope = .unknown := by
  simp [Pred.eval, none, open_, Truth.any, Truth.all]

/-! ## Stability along an extension of the settled environment -/

/-- `later` knows at least what `earlier` knows: the same inputs and policy, at least the same
    records, and every kind that was closed is still closed and gained nothing.

    This is a relation between two environments as evaluation sees them, after conflicts were
    settled. It is narrower than "more evidence was admitted":

    * The inputs are the same, so the cutoff is the same. Two cutoffs are two questions.
    * No record is removed or changed. A later record that conflicts with an earlier one removes
      records from the settled environment, so it is not an extension.
    * A closed kind gains nothing. That is what a completeness statement asserts; if a source
      declared a listing complete and a record of that kind arrives later, the later
      environment is not an extension either.

    `Limits.lean` proves that the last clause cannot be dropped. -/
structure Extends (earlier later : Env) : Prop where
  inputs : later.inputs = earlier.inputs
  params : later.params = earlier.params
  records : ∀ kind record, record ∈ earlier.records kind → record ∈ later.records kind
  closed : ∀ kind, earlier.closed kind = true →
    later.closed kind = true ∧ ∀ record, record ∈ later.records kind → record ∈ earlier.records kind

theorem term_eval_extends {earlier later : Env} (ext : Extends earlier later) (scope : Scope)
    (term : Term) : term.eval later scope = term.eval earlier scope := by
  cases term <;> simp [Term.eval, ext.inputs, ext.params]

/-- Monotonicity along `Extends`: a predicate that is true stays true and one that is false
    stays false. Only `unknown` can change. -/
theorem eval_monotone {earlier later : Env} (ext : Extends earlier later) (pred : Pred) :
    ∀ scope : Scope,
      (pred.eval earlier scope = .true → pred.eval later scope = .true) ∧
        (pred.eval earlier scope = .false → pred.eval later scope = .false) := by
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

/-- Between an environment and an extension of it (`Extends`), a supported decision stays
    supported and a contradicted one stays contradicted. An undetermined decision may become
    either.

    Read the hypothesis before the conclusion. This does not say a decision survives any later
    evidence: it does not cover a listing that was declared complete and was not, a later
    record that conflicts with an earlier one, a withdrawn completeness statement, or a
    different cutoff. -/
theorem definite_decision_is_stable {earlier later : Env} (ext : Extends earlier later)
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
    exact (eval_monotone ext requirement []).1
      ((supported_iff_all_true _).mp h _ (List.mem_map.mpr ⟨requirement, inRequirements, rfl⟩))
  · intro h
    apply (contradicted_iff_some_false _).mpr
    obtain ⟨requirement, inRequirements, value⟩ :=
      List.mem_map.mp ((contradicted_iff_some_false _).mp h)
    exact List.mem_map.mpr ⟨requirement, inRequirements, (eval_monotone ext requirement []).2 value⟩

/-- Evaluation is a function: one contract and one environment have one decision. Stated for
    the record; it holds because `evaluate` is a definition, with no clock, state or choice. -/
theorem evaluation_is_deterministic (env : Env) (requirements : List Pred) (a b : Decision)
    (ha : evaluate env requirements = a) (hb : evaluate env requirements = b) : a = b :=
  ha.symm.trans hb

end Verified.Contract

import Applies.Semantics
import WCL2.Theorems

/-! What is proved about `appliesWhen`. -/

namespace Applies

open Verified.Contract

variable {P : Type}

/-! ## Nothing changes without a condition -/

theorem mem_ofTruth (v : Truth) (values : List Truth) :
    Result.ofTruth v ∈ values.map Result.ofTruth ↔ v ∈ values := by
  constructor
  · intro h
    obtain ⟨w, m, hw⟩ := List.mem_map.mp h
    cases v <;> cases w <;> simp_all [Result.ofTruth]
  · intro h
    exact List.mem_map.mpr ⟨v, h, rfl⟩

/-- A contract none of whose requirements has a condition is decided exactly as Language 1
    decides it. -/
theorem without_conditions (eval : P → Truth) (requirements : List (Requirement P))
    (none_ : ∀ requirement ∈ requirements, requirement.appliesWhen = none) :
    evaluate eval requirements =
      Outcome.ofDecision (Verified.Contract.decide (requirements.map fun requirement => eval requirement.holds)) := by
  have same : requirements.map (result eval) =
      (requirements.map fun requirement => eval requirement.holds).map Result.ofTruth := by
    rw [List.map_map]
    apply List.map_congr_left
    intro requirement m
    simp [result, none_ requirement m]
  unfold evaluate decideAll Verified.Contract.decide
  rw [same]
  have hf := mem_ofTruth .false (requirements.map fun requirement => eval requirement.holds)
  have hu := mem_ofTruth .unknown (requirements.map fun requirement => eval requirement.holds)
  simp only [Result.ofTruth] at hf hu
  by_cases f : Truth.false ∈ requirements.map fun requirement => eval requirement.holds
  · rw [if_pos (hf.mpr f), if_pos f]; rfl
  · rw [if_neg (fun h => f (hf.mp h)), if_neg f]
    by_cases u : Truth.unknown ∈ requirements.map fun requirement => eval requirement.holds
    · rw [if_pos (hu.mpr u), if_pos u]; rfl
    · rw [if_neg (fun h => u (hu.mp h)), if_neg u]
      have notAll : (!((requirements.map fun requirement => eval requirement.holds).map Result.ofTruth).isEmpty &&
          ((requirements.map fun requirement => eval requirement.holds).map Result.ofTruth).all
            (· == Result.notApplicable)) = false := by
        cases (requirements.map fun requirement => eval requirement.holds) with
        | nil => simp
        | cons v rest => cases v <;> simp [Result.ofTruth]
      simp only [notAll, Bool.false_eq_true, if_false]
      rfl

/-! ## What `NOT_APPLICABLE` means -/

/-- A requirement is `NOT_APPLICABLE` exactly when it has a condition and the condition is `FALSE`. -/
theorem notApplicable_iff (eval : P → Truth) (requirement : Requirement P) :
    result eval requirement = .notApplicable ↔
      ∃ condition, requirement.appliesWhen = some condition ∧ eval condition = .false := by
  unfold result
  cases h : requirement.appliesWhen with
  | none => cases eval requirement.holds <;> simp [Result.ofTruth]
  | some condition =>
    cases hc : eval condition <;> simp [hc] <;> cases eval requirement.holds <;> simp [Result.ofTruth]

/-- A requirement is `FALSE` only where it applies: its condition, if any, is `TRUE`. So a
    requirement that does not apply never makes a contract `CONTRADICTED`. -/
theorem false_only_where_it_applies (eval : P → Truth) (requirement : Requirement P)
    (h : result eval requirement = .false) :
    eval requirement.holds = .false ∧ ∀ condition, requirement.appliesWhen = some condition → eval condition = .true := by
  unfold result at h
  cases hw : requirement.appliesWhen with
  | none =>
    rw [hw] at h
    refine ⟨?_, fun _ c => by simp at c⟩
    cases hv : eval requirement.holds <;> simp_all [Result.ofTruth]
  | some condition =>
    rw [hw] at h
    cases hc : eval condition <;> simp only [hc] at h <;> try contradiction
    refine ⟨?_, fun c e => by simp at e; subst e; exact hc⟩
    cases hv : eval requirement.holds <;> simp_all [Result.ofTruth]

/-- A contract is `NOT_APPLICABLE` exactly when it has a requirement and none of them applies. -/
theorem outcome_notApplicable_iff (eval : P → Truth) (requirements : List (Requirement P)) :
    evaluate eval requirements = .notApplicable ↔
      requirements ≠ [] ∧ ∀ requirement ∈ requirements, result eval requirement = .notApplicable := by
  unfold evaluate decideAll
  constructor
  · intro h
    split at h
    · contradiction
    · split at h
      · contradiction
      · split at h
        · rename_i hall
          simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff, List.all_eq_true,
            beq_iff_eq, List.mem_map] at hall
          refine ⟨fun e => by simp [e] at hall, fun requirement m => hall.2 _ ⟨requirement, m, rfl⟩⟩
        · contradiction
  · rintro ⟨ne, all⟩
    have nf : Result.false ∉ requirements.map (result eval) := by
      intro m
      obtain ⟨r, mr, hr⟩ := List.mem_map.mp m
      rw [all r mr] at hr
      contradiction
    have nu : Result.unknown ∉ requirements.map (result eval) := by
      intro m
      obtain ⟨r, mr, hr⟩ := List.mem_map.mp m
      rw [all r mr] at hr
      contradiction
    have hall : (!(requirements.map (result eval)).isEmpty &&
        (requirements.map (result eval)).all (· == Result.notApplicable)) = true := by
      simp only [Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff, List.all_eq_true,
        beq_iff_eq, List.mem_map]
      refine ⟨by simpa using ne, ?_⟩
      rintro _ ⟨r, mr, rfl⟩
      exact all r mr
    rw [if_neg nf, if_neg nu, if_pos hall]

/-! ## Stability -/

/-- `b` keeps every `TRUE` and `FALSE` of `a`. -/
def KeptTruth (a b : Truth) : Prop := (a = .true → b = .true) ∧ (a = .false → b = .false)

theorem ofTruth_kept {a b : Truth} (k : KeptTruth a b) (h : Result.ofTruth a ≠ .unknown) :
    Result.ofTruth b = Result.ofTruth a := by
  cases a with
  | true => rw [k.1 rfl]
  | false => rw [k.2 rfl]
  | unknown => exact absurd rfl h

/-- A requirement whose value is settled (`TRUE`, `FALSE` or `NOT_APPLICABLE`) keeps it along
    more evidence, for any predicate language whose evaluation is stable. -/
theorem result_kept (eval eval' : P → Truth) (mono : ∀ p, KeptTruth (eval p) (eval' p))
    (requirement : Requirement P) (h : result eval requirement ≠ .unknown) :
    result eval' requirement = result eval requirement := by
  cases hw : requirement.appliesWhen with
  | none =>
    simp only [result, hw] at h ⊢
    exact ofTruth_kept (mono _) h
  | some condition =>
    simp only [result, hw] at h ⊢
    cases hc : eval condition with
    | true =>
      simp only [hc] at h
      simp only [(mono condition).1 hc]
      exact ofTruth_kept (mono _) h
    | false => simp only [(mono condition).2 hc]
    | unknown => simp [hc] at h

/-- A decision that is not `UNDETERMINED` (`SUPPORTED`, `CONTRADICTED` or `NOT_APPLICABLE`) stays
    as it is along more evidence, for any predicate language whose evaluation is stable. -/
theorem decision_is_stable (eval eval' : P → Truth) (mono : ∀ p, KeptTruth (eval p) (eval' p))
    (requirements : List (Requirement P)) (h : evaluate eval requirements ≠ .undetermined) :
    evaluate eval' requirements = evaluate eval requirements := by
  by_cases f : Result.false ∈ requirements.map (result eval)
  · obtain ⟨r, mr, hr⟩ := List.mem_map.mp f
    have still : Result.false ∈ requirements.map (result eval') :=
      List.mem_map.mpr ⟨r, mr, by rw [result_kept eval eval' mono r (by rw [hr]; decide), hr]⟩
    unfold evaluate decideAll
    simp [f, still]
  · have nu : Result.unknown ∉ requirements.map (result eval) := by
      intro u
      apply h
      unfold evaluate decideAll
      simp [f, u]
    have same : requirements.map (result eval') = requirements.map (result eval) := by
      apply List.map_congr_left
      intro r mr
      exact result_kept eval eval' mono r fun e => nu (List.mem_map.mpr ⟨r, mr, e⟩)
    unfold evaluate
    rw [same]

/-! ## Language 2 -/

/-- For RFC 0008's Language 2: along a settled extension, a decision that is not
    `UNDETERMINED` stays as it is. -/
theorem language_2_decision_is_stable {earlier later : Env} (settled : WCL2.Settled earlier later)
    (requirements : List (Requirement WCL2.Pred))
    (h : evaluate (fun p => p.eval earlier []) requirements ≠ .undetermined) :
    evaluate (fun p => p.eval later []) requirements = evaluate (fun p => p.eval earlier []) requirements :=
  decision_is_stable _ _ (fun p => WCL2.eval_monotone settled p []) requirements h

end Applies

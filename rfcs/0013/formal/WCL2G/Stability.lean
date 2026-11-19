import WCL2G.Semantics
import WCL2T.Stability

/-!
Stability along more evidence, with completeness per group.

More evidence may now add a record to a kind that is open as a whole, so long as it doesn't fall
into a group that was declared complete. `GSettled` says so: RFC 0008's `Settled` for the
environment, and every group declared complete stays declared, with no record added to it.
Along it, a requirement that is `TRUE` or `FALSE` stays so, and a decision that is `SUPPORTED`
or `CONTRADICTED` stays so, as in RFC 0008 and RFC 0011.

The proof is RFC 0011's, with one change: where RFC 0011 uses "the kind is closed, so no record
is added", a quantifier here uses "its listing is closed, so no record is added to the listing"
(`ListingKept`), which holds for a whole kind and for a group alike (`listing_kept`).
-/

namespace WCL2G

open Verified.Contract
open WCL2 (Aggregate Judged definite number Settled)
open WCL2T (Kept KeptTruth cmpOpt arith exVal allVal number_kept arith_kept map_kept cmpOpt_kept)

/-- More evidence, with groups: settled as RFC 0008 defines it, and every group declared complete
    stays declared, with no record added to it. -/
structure GSettled (earlier later : GEnv) : Prop where
  base : Settled earlier.base later.base
  groups : ∀ kind field value, earlier.groups kind field value = true →
    later.groups kind field value = true ∧
      ∀ record, record ∈ later.base.records kind → record.get field = some value →
        record ∈ earlier.base.records kind

/-- What a quantifier needs of its listing along more evidence: no record is lost, and a closed
    listing stays closed with no record added. Each record is listed once. -/
structure ListingKept (ce : Bool) (re : List Record) (cl : Bool) (rl : List Record) : Prop where
  sub : ∀ record, record ∈ re → record ∈ rl
  closed : ce = true → cl = true ∧ ∀ record, record ∈ rl → record ∈ re
  nodupE : re.Nodup
  nodupL : rl.Nodup

theorem listing_nodup (env : GEnv) (distinct : WCL2.Distinct env.base) (kind : String)
    (group : Option String) (key : Option Value) : (listing env kind group key).2.Nodup := by
  cases group with
  | none => exact distinct kind
  | some field =>
    cases key with
    | none => exact List.nodup_nil
    | some value => exact (distinct kind).filter _

/-- A whole kind and a group alike keep what a quantifier needs, when the key keeps its value. -/
theorem listing_kept {earlier later : GEnv} (settled : GSettled earlier later) (kind : String)
    (group : Option String) {ke kl : Option Value} (key : Kept ke kl) :
    ListingKept (listing earlier kind group ke).1 (listing earlier kind group ke).2
      (listing later kind group kl).1 (listing later kind group kl).2 := by
  have nodupE := listing_nodup earlier settled.base.earlierDistinct kind group ke
  have nodupL := listing_nodup later settled.base.laterDistinct kind group kl
  cases group with
  | none =>
    exact ⟨settled.base.ext.records kind, settled.base.ext.closed kind, nodupE, nodupL⟩
  | some field =>
    cases ke with
    | none =>
      refine ⟨fun record h => by simp [listing] at h, fun h => by simp [listing] at h, nodupE, nodupL⟩
    | some value =>
      have kl_eq : kl = some value := key value rfl
      subst kl_eq
      refine ⟨?_, ?_, nodupE, nodupL⟩
      · intro record h
        simp only [listing, List.mem_filter, decide_eq_true_eq] at h ⊢
        exact ⟨settled.base.ext.records kind record h.1, h.2⟩
      · intro h
        simp only [listing, Bool.or_eq_true] at h ⊢
        rcases h with closed | declared
        · obtain ⟨stillClosed, nothingNew⟩ := settled.base.ext.closed kind closed
          refine ⟨Or.inl stillClosed, fun record member => ?_⟩
          simp only [List.mem_filter, decide_eq_true_eq] at member ⊢
          exact ⟨nothingNew record member.1, member.2⟩
        · obtain ⟨stillDeclared, nothingNew⟩ := settled.groups kind field value declared
          refine ⟨Or.inr stillDeclared, fun record member => ?_⟩
          simp only [List.mem_filter, decide_eq_true_eq] at member ⊢
          exact ⟨nothingNew record member.1 member.2, member.2⟩

theorem exVal_kept_listing {ce cl : Bool} {re rl : List Record} (lk : ListingKept ce re cl rl)
    (f g : Record → Truth) (keep : ∀ record, KeptTruth (f record) (g record)) :
    KeptTruth (exVal ce (re.map f)) (exVal cl (rl.map g)) := by
  constructor
  · intro h
    unfold exVal at h ⊢
    split at h
    · contradiction
    · obtain ⟨record, member, value⟩ := List.mem_map.mp (any_eq_true.mp h)
      have seen : Truth.any (rl.map g) = .true :=
        any_eq_true.mpr (List.mem_map.mpr ⟨record, lk.sub record member, (keep record).1 value⟩)
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
      have closed : ce = true := by
        cases c : ce with
        | true => rfl
        | false => exact absurd ⟨h, c⟩ guard
      obtain ⟨stillClosed, nothingNew⟩ := lk.closed closed
      have seen : Truth.any (rl.map g) = .false := by
        apply any_eq_false.mpr
        intro value member
        obtain ⟨record, inLater, rfl⟩ := List.mem_map.mp member
        exact (keep record).2 (allFalse _ (List.mem_map.mpr ⟨record, nothingNew record inLater, rfl⟩))
      split
      · rename_i guard'
        rw [stillClosed] at guard'
        exact absurd guard'.2 (by decide)
      · exact seen

theorem allVal_kept_listing {ce cl : Bool} {re rl : List Record} (lk : ListingKept ce re cl rl)
    (f g : Record → Truth) (keep : ∀ record, KeptTruth (f record) (g record)) :
    KeptTruth (allVal ce (re.map f)) (allVal cl (rl.map g)) := by
  constructor
  · intro h
    unfold allVal at h ⊢
    split at h
    · contradiction
    · rename_i guard
      have allTrue := all_eq_true.mp h
      have closed : ce = true := by
        cases c : ce with
        | true => rfl
        | false => exact absurd ⟨h, c⟩ guard
      obtain ⟨stillClosed, nothingNew⟩ := lk.closed closed
      have seen : Truth.all (rl.map g) = .true := by
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
      have seen : Truth.all (rl.map g) = .false :=
        all_eq_false.mpr (List.mem_map.mpr ⟨record, lk.sub record member, (keep record).2 value⟩)
      split
      · rename_i guard
        rw [seen] at guard
        exact absurd guard.1 (by decide)
      · exact seen

/-- Two listings with the same records, each listing a record once, are reorderings. -/
theorem perm_of_same_members {a b : List Record} (na : a.Nodup) (nb : b.Nodup)
    (ab : ∀ record, record ∈ a → record ∈ b) (ba : ∀ record, record ∈ b → record ∈ a) : b.Perm a := by
  apply List.perm_iff_count.mpr
  intro record
  rw [List.Nodup.count nb, List.Nodup.count na]
  have same : record ∈ b ↔ record ∈ a := ⟨ba record, ab record⟩
  simp only [same]

/-- An aggregate with a value keeps it: its listing was closed and every body settled, the later
    listing has exactly the same records, and each body stays settled. -/
theorem aggValue_kept {ce cl : Bool} {re rl : List Record} (lk : ListingKept ce re cl rl)
    (fn : Aggregate) (f g : Record → Truth) (keep : ∀ record, KeptTruth (f record) (g record)) :
    Kept ((fn.value ce (re.map fun record => (record, f record))).map .num)
      ((fn.value cl (rl.map fun record => (record, g record))).map .num) := by
  intro v
  cases h : fn.value ce (re.map fun record => (record, f record)) with
  | none => simp
  | some n =>
    intro hv
    obtain ⟨closed, bodiesSettled⟩ := WCL2.aggregate_value_requires_closed fn _ _ n h
    obtain ⟨stillClosed, nothingNew⟩ := lk.closed closed
    have reordered := perm_of_same_members lk.nodupE lk.nodupL lk.sub nothingNew
    have judged := WCL2.settled_bodies_kept re rl reordered f g (fun record => keep record) bodiesSettled
    rw [stillClosed, WCL2.value_perm fn true judged, ← closed, h]
    exact hv

/-! ## The evaluation, one node at a time -/

theorem eval_ex (env : GEnv) (var kind : String) (group : Option String) (key : Term) (body : Pred)
    (scope : Scope) :
    (Pred.ex var kind group key body).eval env scope =
      exVal (listing env kind group (key.eval env scope)).1
        ((listing env kind group (key.eval env scope)).2.map fun record => body.eval env ((var, record) :: scope)) := by
  simp only [Pred.eval, exVal]

theorem eval_all (env : GEnv) (var kind : String) (group : Option String) (key : Term) (body : Pred)
    (scope : Scope) :
    (Pred.all var kind group key body).eval env scope =
      allVal (listing env kind group (key.eval env scope)).1
        ((listing env kind group (key.eval env scope)).2.map fun record => body.eval env ((var, record) :: scope)) := by
  simp only [Pred.eval, allVal]

theorem eval_aggPred (env : GEnv) (fn : Aggregate) (var kind : String) (group : Option String)
    (key : Term) (body : Pred) (op : Op) (bound : Term) (scope : Scope) :
    (Pred.agg fn var kind group key body op bound).eval env scope =
      cmpOpt op (Term.agg fn var kind group key body |>.eval env scope) (bound.eval env scope) := by
  simp only [Pred.eval, Term.eval]
  cases fn.value _ _ <;> cases bound.eval env scope <;> rfl

theorem eval_cmp (env : GEnv) (op : Op) (left right : Term) (scope : Scope) :
    (Pred.cmp op left right).eval env scope = cmpOpt op (left.eval env scope) (right.eval env scope) := by
  simp only [Pred.eval]
  cases left.eval env scope <;> cases right.eval env scope <;> rfl

theorem eval_arith (env : GEnv) (left right : Term) (scope : Scope) :
    (Term.add left right).eval env scope = arith (· + ·) (left.eval env scope) (right.eval env scope) ∧
    (Term.sub left right).eval env scope = arith (· - ·) (left.eval env scope) (right.eval env scope) ∧
    (Term.mul left right).eval env scope = arith (· * ·) (left.eval env scope) (right.eval env scope) := by
  simp only [Term.eval, arith]
  refine ⟨?_, ?_, ?_⟩ <;> cases number (left.eval env scope) <;> cases number (right.eval env scope) <;> rfl

/-! ## Stability -/

mutual
  /-- A term with a value keeps it along more evidence, groups included. -/
  theorem term_kept {earlier later : GEnv} (settled : GSettled earlier later) :
      (term : Term) → ∀ scope, Kept (term.eval earlier scope) (term.eval later scope)
    | .lit _ _, _ => fun _ h => h
    | .input _, _ => fun v h => by simp only [Term.eval] at h ⊢; rw [settled.base.ext.inputs]; exact h
    | .param _, _ => fun v h => by simp only [Term.eval] at h ⊢; rw [settled.base.ext.params]; exact h
    | .field _ _, _ => fun v h => by simp only [Term.eval] at h ⊢; exact h
    | .add left right, scope => by
      rw [(eval_arith earlier left right scope).1, (eval_arith later left right scope).1]
      exact arith_kept _ (term_kept settled left scope) (term_kept settled right scope)
    | .sub left right, scope => by
      rw [(eval_arith earlier left right scope).2.1, (eval_arith later left right scope).2.1]
      exact arith_kept _ (term_kept settled left scope) (term_kept settled right scope)
    | .mul left right, scope => by
      rw [(eval_arith earlier left right scope).2.2, (eval_arith later left right scope).2.2]
      exact arith_kept _ (term_kept settled left scope) (term_kept settled right scope)
    | .scale factor arg, scope => by
      simp only [Term.eval]
      exact map_kept _ (term_kept settled arg scope)
    | .abs arg, scope => by
      simp only [Term.eval]
      exact map_kept _ (term_kept settled arg scope)
    | .agg fn var kind group key body, scope => by
      simp only [Term.eval]
      exact aggValue_kept (listing_kept settled kind group (term_kept settled key scope)) fn _ _
        fun record => pred_kept settled body ((var, record) :: scope)

  /-- Monotonicity along more evidence, groups included: a requirement that is true stays true
      and one that is false stays false. Only `unknown` can change. -/
  theorem pred_kept {earlier later : GEnv} (settled : GSettled earlier later) :
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
    | .ex var kind group key body, scope => by
      rw [eval_ex, eval_ex]
      exact exVal_kept_listing (listing_kept settled kind group (term_kept settled key scope)) _ _
        fun record => pred_kept settled body ((var, record) :: scope)
    | .all var kind group key body, scope => by
      rw [eval_all, eval_all]
      exact allVal_kept_listing (listing_kept settled kind group (term_kept settled key scope)) _ _
        fun record => pred_kept settled body ((var, record) :: scope)
    | .agg fn var kind group key body op bound, scope => by
      rw [eval_aggPred, eval_aggPred]
      simp only [Term.eval]
      exact cmpOpt_kept op
        (aggValue_kept (listing_kept settled kind group (term_kept settled key scope)) fn _ _
          fun record => pred_kept settled body ((var, record) :: scope))
        (term_kept settled bound scope)
end

theorem eval_monotone {earlier later : GEnv} (settled : GSettled earlier later) (pred : Pred) :
    ∀ scope : Scope,
      (pred.eval earlier scope = .true → pred.eval later scope = .true) ∧
        (pred.eval earlier scope = .false → pred.eval later scope = .false) :=
  pred_kept settled pred

/-- Along more evidence, a supported decision stays supported and a contradicted one stays
    contradicted, with completeness per group. -/
theorem definite_decision_is_stable {earlier later : GEnv} (settled : GSettled earlier later)
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

end WCL2G

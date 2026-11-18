/-!
# RFC 0009 (draft): interval aggregates, at the level of one aggregate

A standalone model, in Lean's core only. It states the proposed reading of `sum` and `count`
over the records of a kind, and proves the four properties the RFC relies on:

* `agrees_when_settled`: over a closed kind with every body settled, the interval is the single
  value RFC 0008 gives (`Aggregate.value`), so nothing changes where RFC 0008 decides;
* `lo_narrows`, `hi_narrows`: along more evidence (bodies settling, records added to a kind that
  was open, the kind becoming closed), the lower bound never falls and the upper bound never
  rises;
* `contains_settled`: the value of any settled extension lies within the interval, so a
  comparison the interval decides is the one the settled value would give;
* `cmp_stable`: a comparison that is `TRUE` or `FALSE` stays so along more evidence.

A record is modelled as the value of its body (`Truth`) and of the summed field (`Int`); for
`count` the field is 1 for every record. The integration into RFC 0008's full model (scopes,
nested predicates, `Settled` environments, reordering) is not done here.
-/

namespace RFC0009

inductive Truth | t | f | u
  deriving DecidableEq, Repr

/-- Each record of a kind: the body's value for it, and the summed field's value. -/
abbrev Judged := List (Truth × Int)

/-- The sum over the records the body holds for: RFC 0008's value, when it has one. -/
def exact : Judged → Int
  | [] => 0
  | (b, v) :: j => exact j + (if b = .t then v else 0)

/-- No body is unknown. -/
def Definite (j : Judged) : Prop := ∀ p ∈ j, p.1 ≠ .u

/-- The least the sum can be: the records the body holds for, and the negative values among
those whose body is unknown. -/
def loSum : Judged → Int
  | [] => 0
  | (b, v) :: j => loSum j + (match b with | .t => v | .u => min v 0 | .f => 0)

/-- The most the sum can be: the records the body holds for, and the positive values among those
whose body is unknown. -/
def hiSum : Judged → Int
  | [] => 0
  | (b, v) :: j => hiSum j + (match b with | .t => v | .u => max v 0 | .f => 0)

/-- The summed field's declared `minimum`, if any: every conforming record's value is at least
it. `nonNegative` is `minimum = 0`. -/
abbrev Minimum := Option Int

/-- A minimum gives an open kind a lower bound only if it is at least 0: then a record not yet seen
can only add. With a negative minimum (or none), unseen records can lower the sum without limit. -/
def boundsOpen : Minimum → Bool
  | some m => decide (0 ≤ m)
  | none => false

/-- The lower bound: finite over a closed kind, or over an open kind whose summed field declares
a minimum of at least 0; `none` is −∞. -/
def lo (closed : Bool) (m : Minimum) (j : Judged) : Option Int :=
  if closed = true ∨ boundsOpen m = true then some (loSum j) else none

/-- The upper bound: finite only over a closed kind; `none` is +∞. -/
def hi (closed : Bool) (j : Judged) : Option Int :=
  if closed = true then some (hiSum j) else none

/-- RFC 0008's value of `sum` over the same records (`Aggregate.value`, for `sum` and `count`). -/
def value0008 (closed : Bool) (j : Judged) : Option Int :=
  if closed = true ∧ (j.all fun p => p.1 ≠ .u) = true then some (exact j) else none

/-! ## More evidence -/

/-- A body's value along more evidence: `TRUE` and `FALSE` stay; `unknown` may become anything
(RFC 0008's `eval_monotone`). -/
def refineT : Truth → Truth → Prop
  | .t, b => b = .t
  | .f, b => b = .f
  | .u, _ => True

/-- The same records, in the same order, each body refined. -/
inductive Pointwise : Judged → Judged → Prop
  | nil : Pointwise [] []
  | cons {b b' : Truth} {v : Int} {j j' : Judged} :
      refineT b b' → Pointwise j j' → Pointwise ((b, v) :: j) ((b', v) :: j')

/-- `j'` (closed `c'`) is `j` (closed `c`) with more evidence: its records refined, followed by
records added, which only an open kind may gain; a closed kind stays closed. Every conforming
record is at least the field's declared minimum. -/
structure Refines (m : Minimum) (c : Bool) (j : Judged) (c' : Bool) (j' : Judged) : Prop where
  split : ∃ a e, j' = a ++ e ∧ Pointwise j a ∧ (c = true → e = [] ∧ c' = true)
  conform : ∀ k, m = some k → ∀ p ∈ j', k ≤ p.2

/-- `x` is at most `y`, as lower bounds (`none` is −∞). -/
def LoLe : Option Int → Option Int → Prop
  | none, _ => True
  | some a, some b => a ≤ b
  | some _, none => False

/-- `x` is at most `y`, as upper bounds (`none` is +∞). -/
def HiLe : Option Int → Option Int → Prop
  | _, none => True
  | some a, some b => a ≤ b
  | none, some _ => False

/-! ## Lemmas -/

theorem loSum_append (a e : Judged) : loSum (a ++ e) = loSum a + loSum e := by
  induction a with
  | nil => simp [loSum]
  | cons p a ih => obtain ⟨b, v⟩ := p; simp only [List.cons_append, loSum, ih]; omega

theorem loSum_nonneg (e : Judged) (h : ∀ p ∈ e, 0 ≤ p.2) : 0 ≤ loSum e := by
  induction e with
  | nil => simp [loSum]
  | cons p e ih =>
    obtain ⟨b, v⟩ := p
    have hv : 0 ≤ v := h (b, v) (by simp)
    have he := ih (fun q hq => h q (by simp [hq]))
    cases b <;> simp only [loSum] <;> omega

theorem pointwise_lo {j a : Judged} (h : Pointwise j a) : loSum j ≤ loSum a := by
  induction h with
  | nil => simp [loSum]
  | @cons b b' v _ _ hb _ ih =>
    cases b <;> cases b' <;> simp_all [refineT, loSum] <;> omega

theorem pointwise_hi {j a : Judged} (h : Pointwise j a) : hiSum a ≤ hiSum j := by
  induction h with
  | nil => simp [hiSum]
  | @cons b b' v _ _ hb _ ih =>
    cases b <;> cases b' <;> simp_all [refineT, hiSum] <;> omega

theorem definite_sums {j : Judged} (h : Definite j) : loSum j = exact j ∧ hiSum j = exact j := by
  induction j with
  | nil => simp [loSum, hiSum, exact]
  | cons p j ih =>
    obtain ⟨b, v⟩ := p
    have hb : b ≠ .u := h (b, v) (by simp)
    have := ih (fun q hq => h q (by simp [hq]))
    cases b <;> simp_all [loSum, hiSum, exact]

/-! ## The four properties -/

/-- Where RFC 0008 gives a value, the interval is that single value. -/
theorem agrees_when_settled (m : Minimum) (j : Judged) (n : Int)
    (h : value0008 true j = some n) : lo true m j = some n ∧ hi true j = some n := by
  have hd : Definite j := by
    intro p hp hu
    simp only [value0008] at h
    split at h
    · rename_i hc
      have := List.all_eq_true.mp hc.2 p hp
      simp_all
    · simp at h
  have hn : exact j = n := by simp only [value0008] at h; split at h <;> simp_all
  have := definite_sums hd
  simp [lo, hi, this.1, this.2, hn]

/-- More evidence never lowers the lower bound. -/
theorem lo_narrows {m : Minimum} {c c' : Bool} {j j' : Judged} (r : Refines m c j c' j') :
    LoLe (lo c m j) (lo c' m j') := by
  obtain ⟨a, e, rfl, hp, hc⟩ := r.split
  by_cases h : c = true ∨ boundsOpen m = true
  · have hla := pointwise_lo hp
    have hle : 0 ≤ loSum e := by
      by_cases hcl : c = true
      · simp [(hc hcl).1, loSum]
      · have hb : boundsOpen m = true := by simp_all
        cases hm : m with
        | none => simp [hm, boundsOpen] at hb
        | some k =>
          have hk : 0 ≤ k := by simpa [hm, boundsOpen] using hb
          exact loSum_nonneg e (fun p hp' => by
            have := r.conform k hm p (by simp [hp'])
            omega)
    have h' : c' = true ∨ boundsOpen m = true := by
      rcases h with h | h
      · exact Or.inl (hc h).2
      · exact Or.inr h
    simp only [lo, if_pos h, if_pos h', LoLe, loSum_append]
    omega
  · simp [lo, if_neg h, LoLe]

/-- More evidence never raises the upper bound. -/
theorem hi_narrows {m : Minimum} {c c' : Bool} {j j' : Judged} (r : Refines m c j c' j') :
    HiLe (hi c' j') (hi c j) := by
  obtain ⟨a, e, rfl, hp, hc⟩ := r.split
  by_cases h : c = true
  · obtain ⟨he, hc'⟩ := hc h
    subst he
    simp only [List.append_nil, hi, if_pos h, if_pos hc', HiLe]
    exact pointwise_hi hp
  · simp [hi, h, HiLe]

/-- The value of any settled extension lies within the interval. -/
theorem contains_settled {m : Minimum} {c : Bool} {j j' : Judged} (r : Refines m c j true j')
    (hd : Definite j') : LoLe (lo c m j) (some (exact j')) ∧ HiLe (some (exact j')) (hi c j) := by
  have hs := definite_sums hd
  have hl := lo_narrows r
  have hh := hi_narrows r
  simp only [lo, hi, true_or, if_true, hs.1, hs.2] at hl hh
  exact ⟨hl, hh⟩

/-! ## Comparing an interval with a value -/

inductive Op | eq | ne | lt | le | gt | ge
  deriving DecidableEq, Repr

/-- The lower bound is above `x` (false for −∞). -/
def loAbove (l : Option Int) (x : Int) : Bool := match l with | some l => decide (l > x) | none => false
/-- The lower bound is at least `x`. -/
def loAtLeast (l : Option Int) (x : Int) : Bool := match l with | some l => decide (l ≥ x) | none => false
/-- The upper bound is below `x` (false for +∞). -/
def hiBelow (h : Option Int) (x : Int) : Bool := match h with | some h => decide (h < x) | none => false
/-- The upper bound is at most `x`. -/
def hiAtMost (h : Option Int) (x : Int) : Bool := match h with | some h => decide (h ≤ x) | none => false

/-- Every value in `[l, h]` satisfies `op x`. -/
def allIn : Op → Option Int → Option Int → Int → Bool
  | .le, _, h, x => hiAtMost h x
  | .lt, _, h, x => hiBelow h x
  | .ge, l, _, x => loAtLeast l x
  | .gt, l, _, x => loAbove l x
  | .eq, l, h, x => loAtLeast l x && hiAtMost h x
  | .ne, l, h, x => loAbove l x || hiBelow h x

/-- No value in `[l, h]` satisfies `op x`. -/
def noneIn : Op → Option Int → Option Int → Int → Bool
  | .le, l, _, x => loAbove l x
  | .lt, l, _, x => loAtLeast l x
  | .ge, _, h, x => hiBelow h x
  | .gt, _, h, x => hiAtMost h x
  | .eq, l, h, x => loAbove l x || hiBelow h x
  | .ne, l, h, x => loAtLeast l x && hiAtMost h x

/-- `[lo, hi] op x`: `TRUE` if every value in the interval satisfies it, `FALSE` if none does,
`unknown` otherwise. -/
def cmpI (op : Op) (l h : Option Int) (x : Int) : Truth :=
  if allIn op l h x then .t else if noneIn op l h x then .f else .u

/-- The interval is not empty. -/
def Nonempty (l h : Option Int) : Prop := ∀ a b, l = some a → h = some b → a ≤ b

theorem loSum_le_hiSum (j : Judged) : loSum j ≤ hiSum j := by
  induction j with
  | nil => simp [loSum, hiSum]
  | cons p j ih => obtain ⟨b, v⟩ := p; cases b <;> simp only [loSum, hiSum] <;> omega

/-- The bounds of any aggregate make a nonempty interval. -/
theorem bounds_nonempty (c : Bool) (m : Minimum) (j : Judged) : Nonempty (lo c m j) (hi c j) := by
  intro a b ha hb
  simp only [lo, hi] at ha hb
  split at ha <;> split at hb <;> simp_all
  subst ha; subst hb; exact loSum_le_hiSum j

theorem loAbove_mono {l l' : Option Int} {x : Int} (hl : LoLe l l') : loAbove l x → loAbove l' x := by
  cases l <;> cases l' <;> simp_all [loAbove, LoLe] <;> omega
theorem loAtLeast_mono {l l' : Option Int} {x : Int} (hl : LoLe l l') : loAtLeast l x → loAtLeast l' x := by
  cases l <;> cases l' <;> simp_all [loAtLeast, LoLe] <;> omega
theorem hiBelow_mono {h h' : Option Int} {x : Int} (hh : HiLe h' h) : hiBelow h x → hiBelow h' x := by
  cases h <;> cases h' <;> simp_all [hiBelow, HiLe] <;> omega
theorem hiAtMost_mono {h h' : Option Int} {x : Int} (hh : HiLe h' h) : hiAtMost h x → hiAtMost h' x := by
  cases h <;> cases h' <;> simp_all [hiAtMost, HiLe] <;> omega

theorem allIn_mono (op : Op) (x : Int) {l h l' h' : Option Int} (hl : LoLe l l') (hh : HiLe h' h) :
    allIn op l h x → allIn op l' h' x := by
  have a1 := @loAbove_mono l l' x hl; have a2 := @loAtLeast_mono l l' x hl
  have a3 := @hiBelow_mono h h' x hh; have a4 := @hiAtMost_mono h h' x hh
  cases op <;> simp only [allIn, Bool.and_eq_true, Bool.or_eq_true]
  · exact fun ⟨p, q⟩ => ⟨a2 p, a4 q⟩
  · exact Or.imp a1 a3
  · exact a3
  · exact a4
  · exact a1
  · exact a2

theorem noneIn_mono (op : Op) (x : Int) {l h l' h' : Option Int} (hl : LoLe l l') (hh : HiLe h' h) :
    noneIn op l h x → noneIn op l' h' x := by
  have a1 := @loAbove_mono l l' x hl; have a2 := @loAtLeast_mono l l' x hl
  have a3 := @hiBelow_mono h h' x hh; have a4 := @hiAtMost_mono h h' x hh
  cases op <;> simp only [noneIn, Bool.and_eq_true, Bool.or_eq_true]
  · exact Or.imp a1 a3
  · exact fun ⟨p, q⟩ => ⟨a2 p, a4 q⟩
  · exact a2
  · exact a1
  · exact a4
  · exact a3

/-- Over a nonempty interval, a comparison cannot hold for every value and for none. -/
theorem not_both (op : Op) (x : Int) {l h : Option Int} (ne : Nonempty l h) :
    ¬ (allIn op l h x = true ∧ noneIn op l h x = true) := by
  cases l <;> cases h <;> cases op <;>
    simp_all [allIn, noneIn, loAbove, loAtLeast, hiBelow, hiAtMost, Nonempty] <;> omega

/-- A settled comparison stays settled along more evidence. -/
theorem cmp_stable (op : Op) (x : Int) {l h l' h' : Option Int}
    (hl : LoLe l l') (hh : HiLe h' h) (ne' : Nonempty l' h') :
    (cmpI op l h x = .t → cmpI op l' h' x = .t) ∧ (cmpI op l h x = .f → cmpI op l' h' x = .f) := by
  have ha := allIn_mono op x hl hh
  have hn := noneIn_mono op x hl hh
  have hb := not_both op x ne'
  constructor
  · intro h1
    simp only [cmpI] at h1 ⊢
    split at h1
    · rw [if_pos (ha (by assumption))]
    · split at h1 <;> simp at h1
  · intro h1
    simp only [cmpI] at h1 ⊢
    split at h1
    · simp at h1
    · split at h1
      · have : noneIn op l' h' x = true := hn (by assumption)
        have : allIn op l' h' x = false := by
          cases h2 : allIn op l' h' x <;> simp_all
        simp_all
      · simp at h1

/-- A comparison of two numbers, as Language 1 makes it. -/
def holds : Op → Int → Int → Bool
  | .eq, n, x => decide (n = x)
  | .ne, n, x => decide (n ≠ x)
  | .lt, n, x => decide (n < x)
  | .le, n, x => decide (n ≤ x)
  | .gt, n, x => decide (n > x)
  | .ge, n, x => decide (n ≥ x)

/-- Where RFC 0008 gives a value, the comparison is RFC 0008's. -/
theorem cmp_agrees (op : Op) (x n : Int) :
    cmpI op (some n) (some n) x = if holds op n x then .t else .f := by
  cases op <;> simp only [cmpI, allIn, noneIn, loAbove, loAtLeast, hiBelow, hiAtMost, holds] <;>
    by_cases h1 : n < x <;> by_cases h2 : n = x <;> simp_all
  all_goals (repeat' split) <;> intros <;> first | rfl | omega | (exfalso; omega) | simp_all <;> omega

/-! ## The worked example: F007's payment verdict (RFC 0009, Motivation) -/

/-- Settlements closed: €300 (unknown whether reversed: reversals open) and €100 (reversal
seen). RFC 0008 has no value; the interval is [0, 300], so `≤ 300` is `TRUE`. -/
example : value0008 true [(.u, 30000), (.f, 10000)] = none := by decide
example : cmpI .le (lo true none [(.u, 30000), (.f, 10000)]) (hi true [(.u, 30000), (.f, 10000)]) 30000
    = .t := by decide

/-- Settlements open: €250 and €100 seen, none reversed (reversals closed). The amount declares
`minimum` 0 (`nonNegative`), so the interval is [350, +∞) and `≤ 300` is `FALSE`. -/
example : value0008 false [(.t, 25000), (.t, 10000)] = none := by decide
example : cmpI .le (lo false (some 0) [(.t, 25000), (.t, 10000)]) (hi false [(.t, 25000), (.t, 10000)]) 30000
    = .f := by decide

/-- A positive minimum (say one cent) bounds an open kind the same way. -/
example : cmpI .le (lo false (some 1) [(.t, 25000), (.t, 10000)]) (hi false [(.t, 25000), (.t, 10000)]) 30000
    = .f := by decide

/-- Without a minimum, or with a negative one, an open kind says nothing. -/
example : cmpI .le (lo false none [(.t, 25000), (.t, 10000)]) (hi false [(.t, 25000), (.t, 10000)]) 30000
    = .u := by decide
example : cmpI .le (lo false (some (-100)) [(.t, 25000), (.t, 10000)]) (hi false [(.t, 25000), (.t, 10000)]) 30000
    = .u := by decide

end RFC0009

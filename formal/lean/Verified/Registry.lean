namespace Verified

/-!
The procedural states of a registered claim, as an audit of a claim registry's log finds them
(protocols/claim-registration/v1/SPEC.md, section 4, audit).

Claims, agreements and units are abstracted to numbers; signatures, digests, documents and times
are assumed to have been checked. A unit stands for the pair of unit key and nullifier. `step`
is the audit's rule for one entry; `run` reads a log from its start. The theorems establish that
a final state is never left and that disputes never change a claim's state, that at most one claim
holds a unit in any log an audit accepts, disputes included, that a registration respects its
agreement's limit on open claims, and that a supersession is followed by the registration of its
replacement and nothing else.
-/

inductive RegState where
  | opened
  | answered
  | refused
  | expired
  | withdrawn
  | superseded
  deriving DecidableEq, Repr

/-- An open claim, or one answered with evidence, holds its unit by its state. -/
def RegState.holds : RegState → Bool
  | .opened | .answered => true
  | _ => false

/-- Refused, expired, withdrawn and superseded claims are closed for good. -/
def RegState.final : RegState → Bool
  | .opened | .answered => false
  | _ => true

/-- A claim's dispute, recorded beside its state. -/
inductive RegDispute where
  | none
  | opened
  | upheld
  | rejected
  deriving DecidableEq, Repr

structure RegClaim where
  id : Nat
  agreement : Nat
  unit : Nat
  state : RegState
  dispute : RegDispute
  deriving DecidableEq, Repr

/-- Whether a claim holds its unit: by its state, by an open dispute, or, once refused, by the
    claimant's upheld dispute of the refusal. -/
def RegClaim.holds (c : RegClaim) : Bool :=
  c.state.holds || c.dispute == .opened || (c.state == .refused && c.dispute == .upheld)

/-- An audit so far: the registered claims, and a replacement the next entry must register. -/
structure RegLog where
  claims : List RegClaim
  replacing : Option Nat
  deriving Repr

def RegLog.empty : RegLog := ⟨[], none⟩

/-- One log entry. `register` carries the limit of the agreement the claim is made under. -/
inductive RegEvent where
  | register (id agreement unit limit : Nat)
  | answer (id : Nat)
  | refuse (id : Nat)
  | expire (id : Nat)
  | withdraw (id : Nat)
  | supersede (id replacement : Nat)
  | openDispute (id : Nat)
  | resolveDispute (id : Nat) (upheld : Bool)
  deriving Repr

def openUnder (cs : List RegClaim) (agreement : Nat) : Nat :=
  (cs.filter (fun c => c.agreement == agreement && c.state == .opened)).length

def onlyOpen (c : RegClaim) : Bool := c.state == .opened

/-- What the claimant may close by a notice: an open claim, or one answered with evidence, that is
    not under an open dispute. A dispute is settled first. -/
def claimantMay (c : RegClaim) : Bool :=
  (c.state == .opened || c.state == .answered) && c.dispute != .opened

def closeOne (id : Nat) (allowed : RegClaim → Bool) (next : RegState) (c : RegClaim) : RegClaim :=
  if c.id == id && allowed c then { c with state := next } else c

def closeStep (s : RegLog) (id : Nat) (allowed : RegClaim → Bool) (next : RegState)
    (replacing : Option Nat) : Option RegLog :=
  if s.replacing.isNone && s.claims.any (fun c => c.id == id && allowed c) then
    some ⟨s.claims.map (closeOne id allowed next), replacing⟩
  else none

/-- A refused claim, or one answered with evidence, that was never disputed. -/
def disputable (c : RegClaim) : Bool :=
  (c.state == .refused || c.state == .answered) && c.dispute == .none

/-- No other claim holds `c`'s unit. -/
def unitFreeFor (cs : List RegClaim) (c : RegClaim) : Bool :=
  !(cs.any (fun d => d.unit == c.unit && d.holds && d != c))

def openOne (id : Nat) (c : RegClaim) : RegClaim :=
  if c.id == id && disputable c then { c with dispute := .opened } else c

def resolveOne (id : Nat) (upheld : Bool) (c : RegClaim) : RegClaim :=
  if c.id == id && c.dispute == .opened then
    { c with dispute := if upheld then .upheld else .rejected }
  else c

def step (s : RegLog) : RegEvent → Option RegLog
  | .register id agreement unit limit =>
    if (s.replacing.isNone || s.replacing == some id)
        && !(s.claims.any (fun c => c.id == id))
        && !(s.claims.any (fun c => c.unit == unit && c.holds))
        && decide (openUnder s.claims agreement < limit) then
      some ⟨s.claims ++ [⟨id, agreement, unit, .opened, .none⟩], none⟩
    else none
  | .answer id => closeStep s id onlyOpen .answered none
  | .refuse id => closeStep s id onlyOpen .refused none
  | .expire id => closeStep s id onlyOpen .expired none
  | .withdraw id => closeStep s id claimantMay .withdrawn none
  | .supersede id replacement => closeStep s id claimantMay .superseded (some replacement)
  | .openDispute id =>
    -- A dispute holds the unit again, so it is opened only where no other claim holds it.
    if s.replacing.isNone && s.claims.any (fun c => c.id == id && disputable c)
        && s.claims.all (fun c => !(c.id == id && disputable c) || unitFreeFor s.claims c) then
      some ⟨s.claims.map (openOne id), none⟩
    else none
  | .resolveDispute id upheld =>
    if s.replacing.isNone && s.claims.any (fun c => c.id == id && c.dispute == .opened) then
      some ⟨s.claims.map (resolveOne id upheld), none⟩
    else none

def run (s : RegLog) : List RegEvent → Option RegLog
  | [] => some s
  | e :: es =>
    match step s e with
    | some s' => run s' es
    | none => none

/-! ### Final states, and disputes beside them -/

theorem closeOne_id_state_final {id : Nat} {allowed : RegClaim → Bool} {next : RegState}
    (hallowed : ∀ c, allowed c = true → c.state.final = false) (c : RegClaim)
    (hf : c.state.final = true) : closeOne id allowed next c = c := by
  have hnot : allowed c = false := by
    cases ha : allowed c
    · rfl
    · rw [hallowed _ ha] at hf
      contradiction
  simp [closeOne, hnot]

/-- The claimant cannot withdraw or replace a claim under an open dispute: it is left as it is. -/
theorem claimant_cannot_close_disputed (id : Nat) (next : RegState) (c : RegClaim)
    (hd : c.dispute = .opened) : closeOne id claimantMay next c = c := by
  simp [closeOne, claimantMay, hd]

/-- A claim in a final state keeps its identity and state, whatever the next entry is. A dispute
    may be recorded beside it; its state does not change. -/
theorem final_claims_persist (s s' : RegLog) (e : RegEvent) (h : step s e = some s')
    (c : RegClaim) (hc : c ∈ s.claims) (hf : c.state.final = true) :
    ∃ c' ∈ s'.claims, c'.id = c.id ∧ c'.state = c.state := by
  have onlyOpen_live : ∀ c, onlyOpen c = true → c.state.final = false := by
    intro c hc
    simp only [onlyOpen, beq_iff_eq] at hc
    simp [hc, RegState.final]
  have claimant_live : ∀ c, claimantMay c = true → c.state.final = false := by
    intro c hc
    simp only [claimantMay, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at hc
    rcases hc.1 with h | h <;> simp [h, RegState.final]
  have closing : ∀ {id allowed next replacing},
      (∀ c, allowed c = true → c.state.final = false) →
      closeStep s id allowed next replacing = some s' →
      ∃ c' ∈ s'.claims, c'.id = c.id ∧ c'.state = c.state := by
    intro id allowed next replacing hallowed hs
    unfold closeStep at hs
    split at hs
    · cases hs
      exact ⟨c, List.mem_map.mpr ⟨c, hc, closeOne_id_state_final hallowed c hf⟩, rfl, rfl⟩
    · contradiction
  cases e with
  | register id agreement unit limit =>
    simp only [step] at h
    split at h
    · cases h
      exact ⟨c, List.mem_append_left _ hc, rfl, rfl⟩
    · contradiction
  | answer id => exact closing onlyOpen_live h
  | refuse id => exact closing onlyOpen_live h
  | expire id => exact closing onlyOpen_live h
  | withdraw id => exact closing claimant_live h
  | supersede id replacement => exact closing claimant_live h
  | openDispute id =>
    simp only [step] at h
    split at h
    · cases h
      refine ⟨openOne id c, List.mem_map.mpr ⟨c, hc, rfl⟩, ?_, ?_⟩ <;>
        (unfold openOne; split <;> rfl)
    · contradiction
  | resolveDispute id upheld =>
    simp only [step] at h
    split at h
    · cases h
      refine ⟨resolveOne id upheld c, List.mem_map.mpr ⟨c, hc, rfl⟩, ?_, ?_⟩ <;>
        (unfold resolveOne; split <;> rfl)
    · contradiction

/-- Opening or resolving a dispute never changes any claim's state. -/
theorem disputes_keep_states (s s' : RegLog) (id : Nat) (upheld : Bool)
    (h : step s (.openDispute id) = some s' ∨ step s (.resolveDispute id upheld) = some s') :
    s'.claims.map (·.state) = s.claims.map (·.state) := by
  rcases h with h | h
  · simp only [step] at h
    split at h
    · cases h
      simp only [List.map_map]
      congr 1
      funext c
      simp only [Function.comp]
      unfold openOne
      split <;> rfl
    · contradiction
  · simp only [step] at h
    split at h
    · cases h
      simp only [List.map_map]
      congr 1
      funext c
      simp only [Function.comp]
      unfold resolveOne
      split <;> rfl
    · contradiction

/-! ### Units -/

/-- Claims that hold the same unit are the same claim, and no two claims share an identifier. -/
def UnitExclusive (cs : List RegClaim) : Prop :=
  (cs.map (·.id)).Nodup ∧
    ∀ c ∈ cs, ∀ d ∈ cs, c.unit = d.unit → c.holds = true → d.holds = true → c = d

theorem eq_of_same_id :
    ∀ {cs : List RegClaim} {c d : RegClaim}, (cs.map (·.id)).Nodup → c ∈ cs → d ∈ cs →
      c.id = d.id → c = d
  | [], _, _, _, hc, _, _ => by simp at hc
  | x :: xs, c, d, hn, hc, hd, he => by
    simp only [List.map_cons, List.nodup_cons, List.mem_map, not_exists, not_and] at hn
    simp only [List.mem_cons] at hc hd
    rcases hc with rfl | hc <;> rcases hd with rfl | hd
    · rfl
    · exact absurd he.symm (hn.1 d hd)
    · exact absurd he (hn.1 c hc)
    · exact eq_of_same_id hn.2 hc hd he

/-- A map that keeps every claim's identifier keeps them distinct. -/
theorem map_keeps_ids {cs : List RegClaim} (f : RegClaim → RegClaim) (hf : ∀ c, (f c).id = c.id)
    (h : (cs.map (·.id)).Nodup) : ((cs.map f).map (·.id)).Nodup := by
  have : (cs.map f).map (·.id) = cs.map (·.id) := by
    simp only [List.map_map]
    congr 1
    funext c
    exact hf c
  rw [this]
  exact h

/-- A map that keeps units and never makes a claim hold a unit it did not hold keeps units
    exclusive. -/
theorem map_preserves_exclusive {cs : List RegClaim} (f : RegClaim → RegClaim)
    (hid : ∀ c, (f c).id = c.id) (hunit : ∀ c, (f c).unit = c.unit)
    (hholds : ∀ c, (f c).holds = true → c.holds = true) (inv : UnitExclusive cs) :
    UnitExclusive (cs.map f) := by
  refine ⟨map_keeps_ids f hid inv.1, ?_⟩
  intro c' hc' d' hd' hu hcs hds
  simp only [List.mem_map] at hc' hd'
  obtain ⟨c, hcm, rfl⟩ := hc'
  obtain ⟨d, hdm, rfl⟩ := hd'
  rw [hunit, hunit] at hu
  rw [inv.2 c hcm d hdm hu (hholds c hcs) (hholds d hds)]

theorem closeStep_preserves_exclusive {s s' : RegLog} {id : Nat} {allowed : RegClaim → Bool}
    {next : RegState} {replacing : Option Nat}
    (hallowed : ∀ c, allowed c = true → c.state.holds = true)
    (h : closeStep s id allowed next replacing = some s') (inv : UnitExclusive s.claims) :
    UnitExclusive s'.claims := by
  unfold closeStep at h
  split at h
  · cases h
    refine map_preserves_exclusive _ ?_ ?_ ?_ inv
    · intro c; unfold closeOne; split <;> rfl
    · intro c; unfold closeOne; split <;> rfl
    · -- Only a claim that holds its unit by its state is closed.
      intro c hc
      unfold closeOne at hc
      split at hc
      · rename_i hcond
        simp only [Bool.and_eq_true] at hcond
        simp [RegClaim.holds, hallowed c hcond.2]
      · exact hc
  · contradiction

theorem register_preserves_exclusive {cs : List RegClaim} {id agreement unit : Nat}
    (inv : UnitExclusive cs) (hfresh : cs.any (fun c => c.id == id) = false)
    (hfree : cs.any (fun c => c.unit == unit && c.holds) = false) :
    UnitExclusive (cs ++ [⟨id, agreement, unit, .opened, .none⟩]) := by
  have held : ∀ c ∈ cs, c.unit = unit → c.holds = true → False := by
    intro c hc hu hh
    have : cs.any (fun c => c.unit == unit && c.holds) = true :=
      List.any_eq_true.mpr ⟨c, hc, by simp [hu, hh]⟩
    rw [hfree] at this
    contradiction
  refine ⟨?_, ?_⟩
  · simp only [List.map_append, List.map_cons, List.map_nil]
    refine List.nodup_append.mpr ⟨inv.1, by simp, ?_⟩
    intro a ha b hb heq
    simp only [List.mem_singleton] at hb
    simp only [List.mem_map] at ha
    obtain ⟨c, hc, hca⟩ := ha
    have : cs.any (fun c => c.id == id) = true :=
      List.any_eq_true.mpr ⟨c, hc, by rw [beq_iff_eq, hca, heq, hb]⟩
    rw [hfresh] at this
    contradiction
  · intro c hc d hd hu hch hdh
    simp only [List.mem_append, List.mem_singleton] at hc hd
    rcases hc with hc | rfl <;> rcases hd with hd | rfl
    · exact inv.2 c hc d hd hu hch hdh
    · exact (held c hc hu hch).elim
    · exact (held d hd hu.symm hdh).elim
    · rfl

theorem openDispute_preserves_exclusive {cs : List RegClaim} {id : Nat}
    (inv : UnitExclusive cs)
    (hguard : cs.all (fun c => !(c.id == id && disputable c) || unitFreeFor cs c) = true) :
    UnitExclusive (cs.map (openOne id)) := by
  have hid : ∀ c, (openOne id c).id = c.id := by intro c; unfold openOne; split <;> rfl
  have hunit : ∀ c, (openOne id c).unit = c.unit := by intro c; unfold openOne; split <;> rfl
  -- A claim whose dispute was opened: no other claim held its unit.
  have free : ∀ c ∈ cs, (c.id == id && disputable c) = true →
      ∀ d ∈ cs, d.unit = c.unit → d.holds = true → d = c := by
    intro c hc hm d hd hu hh
    have hc' := List.all_eq_true.mp hguard c hc
    simp only [hm, Bool.not_true, Bool.false_or, unitFreeFor, Bool.not_eq_true',
      List.any_eq_false] at hc'
    have := hc' d hd
    simp only [hu, beq_self_eq_true, hh, Bool.true_and, bne_iff_ne, ne_eq] at this
    exact Classical.byContradiction this
  refine ⟨map_keeps_ids _ hid inv.1, ?_⟩
  intro c' hc' d' hd' hu hcs hds
  simp only [List.mem_map] at hc' hd'
  obtain ⟨c, hcm, rfl⟩ := hc'
  obtain ⟨d, hdm, rfl⟩ := hd'
  rw [hunit, hunit] at hu
  by_cases mc : (c.id == id && disputable c) = true <;>
    by_cases md : (d.id == id && disputable d) = true
  · -- Both opened: the same identifier, so the same claim.
    simp only [Bool.and_eq_true, beq_iff_eq] at mc md
    rw [eq_of_same_id inv.1 hcm hdm (mc.1.trans md.1.symm)]
  · have hd : openOne id d = d := by simp [openOne, md]
    rw [hd] at hds
    rw [free c hcm mc d hdm hu.symm hds]
  · have hc : openOne id c = c := by simp [openOne, mc]
    rw [hc] at hcs
    rw [free d hdm md c hcm hu hcs]
  · have hc : openOne id c = c := by simp [openOne, mc]
    have hd : openOne id d = d := by simp [openOne, md]
    rw [hc] at hcs ⊢
    rw [hd] at hds ⊢
    exact inv.2 c hcm d hdm hu hcs hds

/-- Every entry an audit accepts keeps units exclusive. -/
theorem step_preserves_exclusive (s s' : RegLog) (e : RegEvent) (h : step s e = some s')
    (inv : UnitExclusive s.claims) : UnitExclusive s'.claims := by
  have open_holds : ∀ c, onlyOpen c = true → c.state.holds = true := by
    intro c hc
    simp only [onlyOpen, beq_iff_eq] at hc
    simp [hc, RegState.holds]
  have claimant_holds : ∀ c, claimantMay c = true → c.state.holds = true := by
    intro c hc
    simp only [claimantMay, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at hc
    rcases hc.1 with h | h <;> simp [h, RegState.holds]
  cases e with
  | register id agreement unit limit =>
    simp only [step] at h
    split at h
    · rename_i hg
      cases h
      simp only [Bool.and_eq_true, Bool.not_eq_true'] at hg
      exact register_preserves_exclusive inv hg.1.1.2 hg.1.2
    · contradiction
  | answer id => exact closeStep_preserves_exclusive open_holds h inv
  | refuse id => exact closeStep_preserves_exclusive open_holds h inv
  | expire id => exact closeStep_preserves_exclusive open_holds h inv
  | withdraw id => exact closeStep_preserves_exclusive claimant_holds h inv
  | supersede id replacement => exact closeStep_preserves_exclusive claimant_holds h inv
  | openDispute id =>
    simp only [step] at h
    split at h
    · rename_i hg
      cases h
      simp only [Bool.and_eq_true] at hg
      exact openDispute_preserves_exclusive inv hg.2
    · contradiction
  | resolveDispute id upheld =>
    simp only [step] at h
    split at h
    · cases h
      refine map_preserves_exclusive _ ?_ ?_ ?_ inv
      · intro c; unfold resolveOne; split <;> rfl
      · intro c; unfold resolveOne; split <;> rfl
      · intro c hc
        unfold resolveOne at hc
        split at hc
        · rename_i hcond
          simp only [Bool.and_eq_true, beq_iff_eq] at hcond
          simp [RegClaim.holds, hcond.2]
        · exact hc
    · contradiction

theorem run_preserves_exclusive :
    ∀ (es : List RegEvent) (s s' : RegLog), UnitExclusive s.claims → run s es = some s' →
      UnitExclusive s'.claims
  | [], s, s', inv, h => by
    simp only [run, Option.some.injEq] at h
    subst h
    exact inv
  | e :: es, s, s', inv, h => by
    simp only [run] at h
    split at h
    · rename_i s₁ h₁
      exact run_preserves_exclusive es s₁ s' (step_preserves_exclusive s s₁ e h₁ inv) h
    · contradiction

/-- In every log an audit accepts from its start, at most one claim holds each unit, counting
    an open dispute, and a claimant's upheld dispute of a refusal, as holding it. -/
theorem accepted_log_units_exclusive (es : List RegEvent) (s : RegLog)
    (h : run RegLog.empty es = some s) : UnitExclusive s.claims :=
  run_preserves_exclusive es RegLog.empty s
    ⟨by simp [RegLog.empty], by intro c hc; simp [RegLog.empty] at hc⟩ h

/-! ### Limits and supersession -/

/-- A registration the audit accepts leaves at most `limit` open claims under its agreement. -/
theorem register_respects_limit (s s' : RegLog) (id agreement unit limit : Nat)
    (h : step s (.register id agreement unit limit) = some s') :
    openUnder s'.claims agreement ≤ limit := by
  simp only [step] at h
  split at h
  · rename_i hg
    cases h
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hg
    simp only [openUnder, List.filter_append, List.length_append] at hg ⊢
    simp
    omega
  · contradiction

/-- While a supersession awaits its replacement, the only entry an audit accepts is the
    replacement's registration. -/
theorem replacement_comes_next (s s' : RegLog) (e : RegEvent) (r : Nat)
    (hr : s.replacing = some r) (h : step s e = some s') :
    ∃ agreement unit limit, e = .register r agreement unit limit := by
  cases e with
  | register id agreement unit limit =>
    simp only [step, hr] at h
    split at h
    · rename_i hg
      simp only [Bool.and_eq_true, Option.isNone_some, Bool.false_or, beq_iff_eq,
        Option.some.injEq] at hg
      exact ⟨agreement, unit, limit, by rw [hg.1.1.1]⟩
    · contradiction
  | answer id => simp [step, closeStep, hr] at h
  | refuse id => simp [step, closeStep, hr] at h
  | expire id => simp [step, closeStep, hr] at h
  | withdraw id => simp [step, closeStep, hr] at h
  | supersede id replacement => simp [step, closeStep, hr] at h
  | openDispute id => simp [step, hr] at h
  | resolveDispute id upheld => simp [step, hr] at h

end Verified

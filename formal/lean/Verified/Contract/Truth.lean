namespace Verified.Contract

/-!
Strong Kleene truth values (Work Contract Language 1, section 7).

`unknown` is not a kind of falsehood: it says the admitted evidence settles the matter neither
way. Everything else in the language's semantics is built from the three connectives here.
-/

inductive Truth where
  | true | false | unknown
  deriving DecidableEq, Repr

namespace Truth

def not : Truth → Truth
  | .true => .false
  | .false => .true
  | .unknown => .unknown

def and : Truth → Truth → Truth
  | .false, _ => .false
  | _, .false => .false
  | .true, .true => .true
  | _, _ => .unknown

def or : Truth → Truth → Truth
  | .true, _ => .true
  | _, .true => .true
  | .false, .false => .false
  | _, _ => .unknown

/-- Conjunction of any number of values: the empty conjunction is true. -/
def all (values : List Truth) : Truth := values.foldr and .true

/-- Disjunction of any number of values: the empty disjunction is false. -/
def any (values : List Truth) : Truth := values.foldr or .false

/-- The information order: `unknown` may become either definite value; a definite value stays. -/
def Refines (a b : Truth) : Prop := a = .unknown ∨ a = b

end Truth

/-- The published truth tables, all 9 + 9 + 3 entries. -/
theorem truth_tables :
    (Truth.and .true .true = .true ∧ Truth.and .true .false = .false ∧
      Truth.and .true .unknown = .unknown ∧ Truth.and .false .true = .false ∧
      Truth.and .false .false = .false ∧ Truth.and .false .unknown = .false ∧
      Truth.and .unknown .true = .unknown ∧ Truth.and .unknown .false = .false ∧
      Truth.and .unknown .unknown = .unknown) ∧
    (Truth.or .true .true = .true ∧ Truth.or .true .false = .true ∧
      Truth.or .true .unknown = .true ∧ Truth.or .false .true = .true ∧
      Truth.or .false .false = .false ∧ Truth.or .false .unknown = .unknown ∧
      Truth.or .unknown .true = .true ∧ Truth.or .unknown .false = .unknown ∧
      Truth.or .unknown .unknown = .unknown) ∧
    (Truth.not .true = .false ∧ Truth.not .false = .true ∧ Truth.not .unknown = .unknown) := by
  decide

theorem de_morgan (a b : Truth) :
    (a.and b).not = a.not.or b.not ∧ (a.or b).not = a.not.and b.not := by
  cases a <;> cases b <;> decide

theorem not_not (a : Truth) : a.not.not = a := by cases a <;> rfl

theorem and_eq_true {a b : Truth} : a.and b = .true ↔ a = .true ∧ b = .true := by
  cases a <;> cases b <;> decide

theorem and_eq_false {a b : Truth} : a.and b = .false ↔ a = .false ∨ b = .false := by
  cases a <;> cases b <;> decide

theorem or_eq_true {a b : Truth} : a.or b = .true ↔ a = .true ∨ b = .true := by
  cases a <;> cases b <;> decide

theorem or_eq_false {a b : Truth} : a.or b = .false ↔ a = .false ∧ b = .false := by
  cases a <;> cases b <;> decide

theorem not_eq_true {a : Truth} : a.not = .true ↔ a = .false := by cases a <;> decide

theorem not_eq_false {a : Truth} : a.not = .false ↔ a = .true := by cases a <;> decide

/-- A disjunction is true exactly when some member is: a witness is always present. -/
theorem any_eq_true {values : List Truth} : Truth.any values = .true ↔ Truth.true ∈ values := by
  induction values with
  | nil => simp [Truth.any]
  | cons head tail ih =>
    have step : Truth.any (head :: tail) = head.or (Truth.any tail) := rfl
    rw [step, or_eq_true, ih]
    constructor
    · rintro (h | h)
      · exact h ▸ List.mem_cons_self
      · exact List.mem_cons_of_mem _ h
    · intro h
      rcases List.mem_cons.mp h with h | h
      · exact Or.inl h.symm
      · exact Or.inr h

/-- A disjunction is false exactly when every member is. -/
theorem any_eq_false {values : List Truth} :
    Truth.any values = .false ↔ ∀ value ∈ values, value = .false := by
  induction values with
  | nil => simp [Truth.any]
  | cons head tail ih =>
    have step : Truth.any (head :: tail) = head.or (Truth.any tail) := rfl
    rw [step, or_eq_false, ih]
    simp

/-- A conjunction is true exactly when every member is. -/
theorem all_eq_true {values : List Truth} :
    Truth.all values = .true ↔ ∀ value ∈ values, value = .true := by
  induction values with
  | nil => simp [Truth.all]
  | cons head tail ih =>
    have step : Truth.all (head :: tail) = head.and (Truth.all tail) := rfl
    rw [step, and_eq_true, ih]
    simp

/-- A conjunction is false exactly when some member is: a counterexample is always present. -/
theorem all_eq_false {values : List Truth} : Truth.all values = .false ↔ Truth.false ∈ values := by
  induction values with
  | nil => simp [Truth.all]
  | cons head tail ih =>
    have step : Truth.all (head :: tail) = head.and (Truth.all tail) := rfl
    rw [step, and_eq_false, ih]
    constructor
    · rintro (h | h)
      · exact h ▸ List.mem_cons_self
      · exact List.mem_cons_of_mem _ h
    · intro h
      rcases List.mem_cons.mp h with h | h
      · exact Or.inl h.symm
      · exact Or.inr h

end Verified.Contract

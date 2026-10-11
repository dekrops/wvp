import Verified.Contract.Semantics

namespace Verified.Contract

/-!
The type system of Work Contract Language 1 (specification, sections 3 and 5, rule 7), with the
proof that a well-typed contract never compares values of different kinds.
-/

/-- What a value is at run time. Integers, times, decimals and money share one representation;
    the static type keeps their units apart. -/
inductive Shape where
  | text | bool | num
  deriving DecidableEq, Repr

def Ty.shape : Ty → Shape
  | .text => .text
  | .bool => .bool
  | _ => .num

def Value.shape : Value → Shape
  | .text _ => .text
  | .bool _ => .bool
  | .num _ => .num

def Op.ordering : Op → Bool
  | .eq | .ne => false
  | _ => true

/-- The declarations of a contract that typing needs. -/
structure Sig where
  inputs : String → Option Ty
  params : String → Option Ty
  fields : String → String → Option Ty

/-- The kinds of the variables bound by the enclosing quantifiers, innermost first. -/
abbrev Ctx := List (String × String)

def Ctx.get (ctx : Ctx) (var : String) : Option String :=
  (ctx.find? (·.1 == var)).map (·.2)

def Term.ty (sig : Sig) (ctx : Ctx) : Term → Option Ty
  | .lit ty value => if value.shape = ty.shape then some ty else none
  | .input name => sig.inputs name
  | .param name => sig.params name
  | .field var name => (Ctx.get ctx var).bind fun kind => sig.fields kind name

/-- Both sides of a comparison have the same type, currency and scale included, and an order is
    asked only of numbers. -/
def Pred.WellTyped (sig : Sig) : Pred → Ctx → Prop
  | .cmp op left right, ctx =>
    ∃ ty, left.ty sig ctx = some ty ∧ right.ty sig ctx = some ty ∧
      (op.ordering = true → ty.shape = .num)
  | .and left right, ctx => left.WellTyped sig ctx ∧ right.WellTyped sig ctx
  | .or left right, ctx => left.WellTyped sig ctx ∧ right.WellTyped sig ctx
  | .not arg, ctx => arg.WellTyped sig ctx
  | .ex var kind body, ctx => body.WellTyped sig ((var, kind) :: ctx)
  | .all var kind body, ctx => body.WellTyped sig ((var, kind) :: ctx)

/-- An environment fits a contract's declarations: every value present has its declared shape.
    This is what conformance (specification, section 7, steps 1 and 3) establishes. -/
structure Conforms (sig : Sig) (env : Env) : Prop where
  inputs : ∀ name value ty, env.inputs name = some value → sig.inputs name = some ty →
    value.shape = ty.shape
  params : ∀ name value ty, env.params name = some value → sig.params name = some ty →
    value.shape = ty.shape
  records : ∀ kind record, record ∈ env.records kind → ∀ name value ty,
    record.get name = some value → sig.fields kind name = some ty → value.shape = ty.shape

/-- The scope binds, variable for variable, a record of the kind the context promises. -/
inductive Bound (env : Env) : Ctx → Scope → Prop where
  | nil : Bound env [] []
  | cons {var kind : String} {record : Record} {ctx : Ctx} {scope : Scope} :
    record ∈ env.records kind → Bound env ctx scope →
    Bound env ((var, kind) :: ctx) ((var, record) :: scope)

theorem bound_get {env : Env} {ctx : Ctx} {scope : Scope} (bound : Bound env ctx scope)
    (var kind : String) (h : Ctx.get ctx var = some kind) :
    ∃ record, Scope.get scope var = some record ∧ record ∈ env.records kind := by
  induction bound with
  | nil => simp [Ctx.get] at h
  | @cons boundVar boundKind record ctx scope member _ ih =>
    by_cases same : (boundVar == var) = true
    · simp [Ctx.get, List.find?, same] at h
      exact ⟨record, by simp [Scope.get, List.find?, same], h ▸ member⟩
    · have differs : (boundVar == var) = false := by simpa using same
      simp [Ctx.get, List.find?, differs] at h
      obtain ⟨found, get, inRecords⟩ := ih (by simpa [Ctx.get] using h)
      exact ⟨found, by simpa [Scope.get, List.find?, differs] using get, inRecords⟩

/-- A term of a type evaluates, when it evaluates to anything, to a value of that type's shape. -/
theorem term_shape {sig : Sig} {env : Env} (conforms : Conforms sig env) {ctx : Ctx}
    {scope : Scope} (bound : Bound env ctx scope) (term : Term) (ty : Ty) (value : Value)
    (typed : term.ty sig ctx = some ty) (evaluated : term.eval env scope = some value) :
    value.shape = ty.shape := by
  cases term with
  | lit litTy litValue =>
    simp only [Term.ty] at typed
    simp only [Term.eval] at evaluated
    split at typed
    · rename_i fits
      cases typed
      cases evaluated
      exact fits
    · contradiction
  | input name => exact conforms.inputs name value ty evaluated typed
  | param name => exact conforms.params name value ty evaluated typed
  | field var name =>
    simp only [Term.ty] at typed
    simp only [Term.eval] at evaluated
    cases kindOf : Ctx.get ctx var with
    | none => simp [kindOf] at typed
    | some kind =>
      obtain ⟨record, get, member⟩ := bound_get bound var kind kindOf
      simp [kindOf] at typed
      simp [get] at evaluated
      exact conforms.records kind record member name value ty evaluated typed

/-- Two values a comparison may be asked about: the same shape, and numbers if an order. -/
def Comparable (op : Op) (a b : Value) : Prop :=
  a.shape = b.shape ∧ (op.ordering = true → a.shape = .num)

/-- On comparable values a comparison has a definite answer. -/
theorem comparable_is_definite (op : Op) (a b : Value) (h : Comparable op a b) :
    compare op a b ≠ .unknown := by
  obtain ⟨same, ordered⟩ := h
  cases a <;> cases b <;> cases op <;>
    simp_all [Value.shape, Op.ordering, compare, Truth.of] <;>
    split <;> simp

/-- Every comparison evaluation can reach is asked of comparable values. -/
def Pred.Safe (env : Env) : Pred → Scope → Prop
  | .cmp op left right, scope =>
    ∀ a b, left.eval env scope = some a → right.eval env scope = some b → Comparable op a b
  | .and left right, scope => left.Safe env scope ∧ right.Safe env scope
  | .or left right, scope => left.Safe env scope ∧ right.Safe env scope
  | .not arg, scope => arg.Safe env scope
  | .ex var kind body, scope =>
    ∀ record ∈ env.records kind, body.Safe env ((var, record) :: scope)
  | .all var kind body, scope =>
    ∀ record ∈ env.records kind, body.Safe env ((var, record) :: scope)

/-- Type safety. In an environment that fits the contract's declarations, a well-typed predicate
    never compares a number with text, one currency's shape with another kind of value, or asks
    for an order on text or booleans, however the quantifiers are instantiated. -/
theorem wellTyped_safe {sig : Sig} {env : Env} (conforms : Conforms sig env) (pred : Pred) :
    ∀ (ctx : Ctx) (scope : Scope), Bound env ctx scope → pred.WellTyped sig ctx →
      pred.Safe env scope := by
  induction pred with
  | cmp op left right =>
    intro ctx scope bound typed a b evalLeft evalRight
    obtain ⟨ty, typeLeft, typeRight, ordered⟩ := typed
    have shapeLeft := term_shape conforms bound left ty a typeLeft evalLeft
    have shapeRight := term_shape conforms bound right ty b typeRight evalRight
    exact ⟨shapeLeft.trans shapeRight.symm, fun ordering => shapeLeft.trans (ordered ordering)⟩
  | and left right ihl ihr =>
    intro ctx scope bound typed
    exact ⟨ihl ctx scope bound typed.1, ihr ctx scope bound typed.2⟩
  | or left right ihl ihr =>
    intro ctx scope bound typed
    exact ⟨ihl ctx scope bound typed.1, ihr ctx scope bound typed.2⟩
  | not arg ih =>
    intro ctx scope bound typed
    exact ih ctx scope bound typed
  | ex var kind body ih =>
    intro ctx scope bound typed record member
    exact ih ((var, kind) :: ctx) ((var, record) :: scope) (Bound.cons member bound) typed
  | all var kind body ih =>
    intro ctx scope bound typed record member
    exact ih ((var, kind) :: ctx) ((var, record) :: scope) (Bound.cons member bound) typed

/-- So in a well-typed contract a comparison is unknown only because a value is absent, never
    because of what kind of value it is. -/
theorem wellTyped_comparison_unknown_only_if_absent {sig : Sig} {env : Env}
    (conforms : Conforms sig env) {ctx : Ctx} {scope : Scope} (bound : Bound env ctx scope)
    (op : Op) (left right : Term) (typed : (Pred.cmp op left right).WellTyped sig ctx)
    (unknown : (Pred.cmp op left right).eval env scope = .unknown) :
    left.eval env scope = none ∨ right.eval env scope = none := by
  have safe := wellTyped_safe conforms (Pred.cmp op left right) ctx scope bound typed
  simp only [Pred.eval] at unknown
  cases evalLeft : left.eval env scope with
  | none => exact Or.inl rfl
  | some a =>
    cases evalRight : right.eval env scope with
    | none => exact Or.inr rfl
    | some b =>
      simp only [evalLeft, evalRight] at unknown
      exact absurd unknown (comparable_is_definite op a b (safe a b evalLeft evalRight))

/-! ## Acceptance by source -/

/-- A record as a source reported it. -/
structure Fact where
  kind : String
  source : String
  record : Record

/-- The records evaluation sees for a kind: those from a source the contract accepts for it. -/
def accepted (accepts : String → String → Bool) (facts : List Fact) (kind : String) :
    List Record :=
  (facts.filter fun fact => fact.kind == kind && accepts fact.kind fact.source).map (·.record)

def Env.over (base : Env) (accepts : String → String → Bool) (facts : List Fact) : Env :=
  { base with records := accepted accepts facts }

/-- A record from a source the contract does not accept for its kind changes no decision,
    whatever it says. -/
theorem unaccepted_fact_changes_nothing (base : Env) (accepts : String → String → Bool)
    (facts : List Fact) (fact : Fact) (untrusted : accepts fact.kind fact.source = false)
    (requirements : List Pred) :
    evaluate (base.over accepts (fact :: facts)) requirements =
      evaluate (base.over accepts facts) requirements := by
  have same : accepted accepts (fact :: facts) = accepted accepts facts := by
    funext kind
    simp [accepted, List.filter, untrusted]
  simp [Env.over, same]

end Verified.Contract

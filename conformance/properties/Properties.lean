import Generated

/-!
Properties of the reference evaluator, tested on generated cases with fixed seeds.

Nothing here is a proof. A property that passes was not refuted on the cases generated; a
property that fails comes with a counterexample that Plausible has shrunk. The properties in
`holds` are expected to pass. Those in `needsItsPrecondition` are the same statements with one
precondition removed, and are expected to fail: they show the precondition is needed, with a
minimal case each.
-/

open Verified.Contract
open Verified.Contract.Reference
open Plausible
open Generated

namespace Properties

/-- The evaluator on a generated case, as `Reference.run` composes it. -/
def outcome (c : Case) : Except Refusal Outcome := do
  let doc ← match contract c.contract.json with
    | some doc => pure doc
    | none => throw .contractMalformed
  if !wellFormed doc then throw .contractIllFormed
  let raw ← match environment c.env.json with
    | some raw => pure raw
    | none => throw .environmentMalformed
  evaluateDoc doc raw

/-- The value of each requirement, or nothing if the case was refused. -/
def values (c : Case) : Option (List Truth) :=
  match outcome c with
  | .ok o => some (o.requirements.map (·.2))
  | .error _ => none

def withFacts (c : Case) (facts : List Fact) : Case := { c with env.facts := facts }

/-- A definite value stays what it was; `unknown` may become anything. -/
def preserved (before after : Option (List Truth)) : Bool :=
  match before, after with
  | some b, some a =>
    b.length == a.length && (b.zip a).all fun (x, y) => x == .unknown || x == y
  | _, _ => false

/-- A fact the contract accepts, of kind `a` or `b`, with a key no generated fact has. -/
def fresh (f : Fact) (kindB : Bool) : Fact :=
  { f with kind := if kindB then 1 else 0, source := 0, key := 100 }

/-! ## Expected to hold -/

def evaluated (c : Case) : Bool := (values c).isSome

/-- A generated case is evaluated, or its contract is refused as ill-formed. The generator writes
    well-typed contracts and conforming environments; what it does not avoid is static rule 8
    (a conjunction that holds a predicate and its negation, a requirement that negates another),
    which is `CONTRACT_ILL_FORMED`. No other refusal may occur. -/
def generatorIsValid (c : Case) : Bool :=
  match outcome c with
  | .ok _ => true
  | .error .contractIllFormed => true
  | .error _ => false

/-- The decision is the aggregation the definition gives for the requirements' values. -/
def decisionIsAggregation (c : Case) : Bool :=
  match outcome c with
  | .ok o => o.decision == decide (o.requirements.map (·.2))
  | .error _ => true

/-- **Evaluator and definition agree.** Where no two accepted facts of a kind share a key, the
    evaluator's values are those of `Pred.eval` on the environment the specification describes,
    built here without the evaluator. -/
def agreesWithDefinition (c : Case) : Bool :=
  !c.keysDistinct || !evaluated c ||
    values c == some (c.contract.requires.map fun r => r.pred.eval c.settled [])

/-- A fact from a source the contract does not accept changes no value. -/
def unacceptedSourceChangesNothing (c : Case) (f : Fact) : Bool :=
  values (withFacts c (c.env.facts ++ [{ f with source := 2 }])) == values c

/-- A fact of a kind the contract does not declare changes no value. -/
def undeclaredKindChangesNothing (c : Case) (f : Fact) : Bool :=
  values (withFacts c (c.env.facts ++ [{ f with kind := 2 }])) == values c

/-- The order of the facts changes no value. -/
def orderChangesNothing (c : Case) : Bool :=
  values (withFacts c c.env.facts.reverse) == values c

/-- A fact given twice changes no value. -/
def repetitionChangesNothing (c : Case) : Bool :=
  match c.env.facts with
  | [] => true
  | f :: _ => values (withFacts c (c.env.facts ++ [f])) == values c

/-- A completeness statement from a source the contract does not accept changes no value. -/
def unacceptedCompletenessChangesNothing (c : Case) (kindB : Bool) : Bool :=
  values { c with env.complete := c.env.complete ++ [(kindB, 2)] } == values c

/-- **Extension.** One more accepted record, with a new key, of a kind that is not closed,
    leaves every definite value as it was. -/
def extensionPreservesDefiniteValues (c : Case) (f : Fact) (kindB : Bool) : Bool :=
  c.settled.closed (kindName kindB) || !evaluated c ||
    preserved (values c) (values (withFacts c (c.env.facts ++ [fresh f kindB])))

/-! ## Expected to fail: the precondition is needed -/

/-- Extension without "the kind is not closed". -/
def extensionOfAClosedKind (c : Case) (f : Fact) (kindB : Bool) : Bool :=
  !evaluated c || preserved (values c) (values (withFacts c (c.env.facts ++ [fresh f kindB])))

/-- Extension without "a new key": the added record may conflict with one already there. -/
def extensionWithAnExistingKey (c : Case) (f : Fact) (kindB : Bool) : Bool :=
  c.settled.closed (kindName kindB) || !evaluated c ||
    preserved (values c)
      (values (withFacts c (c.env.facts ++ [{ fresh f kindB with key := f.key }])))

/-- Agreement with the definition without "keys are distinct": the settled environment used
    here does not settle conflicts. -/
def agreesWithDefinitionDespiteConflicts (c : Case) : Bool :=
  !evaluated c || values c == some (c.contract.requires.map fun r => r.pred.eval c.settled [])

/-! ## Running them -/

def seed : Nat := 20261012
def instances : Nat := 2000

/-- Runs one property. `some true`: not refuted. `some false`: refuted. `none`: gave up. -/
def check (name : String) (p : Prop) [Testable p] (expectFailure : Bool) : IO Bool := do
  let result ← Testable.checkIO p { numInst := instances, randomSeed := some seed, quiet := true }
  match result with
  | .success _ =>
    IO.println s!"{if expectFailure then "UNEXPECTED " else ""}not refuted   {name}"
    pure (!expectFailure)
  | .gaveUp n =>
    IO.println s!"GAVE UP after {n} discarded cases   {name}"
    pure false
  | .failure _ counterexample shrinks =>
    IO.println s!"{if expectFailure then "refuted, as expected" else "REFUTED"}   {name}   ({shrinks} shrinks)"
    for line in counterexample do IO.println s!"    {line}"
    pure expectFailure

/-- How often a precondition holds among generated cases, so that a pass is not vacuous. -/
def frequency (name : String) (holds : Case → Bool) : IO Unit := do
  let run : Gen Nat := do
    let mut count := 0
    for _ in [0:instances] do
      if holds (← genCase) then count := count + 1
    pure count
  match (runRandWith seed run).run ⟨10⟩ with
  | .ok count => IO.println s!"    {name}: {count} of {instances} generated cases"
  | .error _ => IO.println s!"    {name}: generation failed"

end Properties

open Properties Generated in
def main : IO UInt32 := do
  IO.println s!"Plausible, seed {seed}, {instances} cases a property."
  let mut ok := true
  IO.println "\nExpected to hold:"
  ok := (← check "a generated case is evaluated, or refused by static rule 8 only" (NamedBinder "c" (∀ c : Case, generatorIsValid c = true)) false) && ok
  ok := (← check "the decision is the aggregation of the requirements" (NamedBinder "c" (∀ c : Case, decisionIsAggregation c = true)) false) && ok
  ok := (← check "evaluator and definition agree (distinct keys)" (NamedBinder "c" (∀ c : Case, agreesWithDefinition c = true)) false) && ok
  ok := (← check "a fact from an unaccepted source changes nothing" (NamedBinder "c" (∀ c : Case, NamedBinder "f" (∀ f : Fact, unacceptedSourceChangesNothing c f = true))) false) && ok
  ok := (← check "a fact of an undeclared kind changes nothing" (NamedBinder "c" (∀ c : Case, NamedBinder "f" (∀ f : Fact, undeclaredKindChangesNothing c f = true))) false) && ok
  ok := (← check "the order of facts changes nothing" (NamedBinder "c" (∀ c : Case, orderChangesNothing c = true)) false) && ok
  ok := (← check "a repeated fact changes nothing" (NamedBinder "c" (∀ c : Case, repetitionChangesNothing c = true)) false) && ok
  ok := (← check "completeness from an unaccepted source changes nothing" (NamedBinder "c" (∀ c : Case, NamedBinder "b" (∀ b : Bool, unacceptedCompletenessChangesNothing c b = true))) false) && ok
  ok := (← check "extension of an open kind with a new key preserves definite values" (NamedBinder "c" (∀ c : Case, NamedBinder "f" (∀ f : Fact, NamedBinder "b" (∀ b : Bool, extensionPreservesDefiniteValues c f b = true)))) false) && ok
  IO.println "\nExpected to fail, each showing that a precondition is needed:"
  ok := (← check "extension of a closed kind" (NamedBinder "c" (∀ c : Case, NamedBinder "f" (∀ f : Fact, NamedBinder "b" (∀ b : Bool, extensionOfAClosedKind c f b = true)))) true) && ok
  ok := (← check "extension with a key already present" (NamedBinder "c" (∀ c : Case, NamedBinder "f" (∀ f : Fact, NamedBinder "b" (∀ b : Bool, extensionWithAnExistingKey c f b = true)))) true) && ok
  ok := (← check "agreement with the definition where keys collide" (NamedBinder "c" (∀ c : Case, agreesWithDefinitionDespiteConflicts c = true)) true) && ok
  IO.println "\nHow often the preconditions hold:"
  frequency "the case is evaluated" evaluated
  frequency "keys are distinct" (·.keysDistinct)
  frequency "kind a is not closed" (fun c => !c.settled.closed "a")
  frequency "some requirement is definite" (fun c => match values c with
    | some vs => vs.any (· != .unknown) | none => false)
  frequency "the decision is SUPPORTED" (fun c => match outcome c with
    | .ok o => o.decision == .supported | .error _ => false)
  frequency "the decision is CONTRADICTED" (fun c => match outcome c with
    | .ok o => o.decision == .contradicted | .error _ => false)
  return (if ok then 0 else 1)

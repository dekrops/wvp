import Verified.Contract.Reference
import Plausible

/-!
Small, well-typed contracts and environments of Work Contract Language 1, as data that can be
generated, shrunk, written in the wire format, and read as terms of the semantic definition.

Every generated contract has the same vocabulary, so that well-typedness holds by construction:
two kinds, `a` and `b`, each with a text key `id`, an optional integer `n` and an optional
boolean `f`. What varies is the requirements, the accepted sources, the conflict policy, and the
environment: facts from accepted and unaccepted sources and of an undeclared kind, with fields
present or absent, keys that collide or do not, and completeness statements.
-/

open Lean (Json)
open Verified.Contract
open Plausible

namespace Generated

/-- The body of a requirement. `x` is the variable the requirement binds, `y` the one an inner
    quantifier binds. -/
inductive Body where
  /-- `v.n op lit`, with `v` the inner variable if `inner` and one is bound. -/
  | num (op : Fin 6) (inner : Bool) (lit : Int)
  /-- `x.n op y.n`. Outside an inner quantifier it is `x.n op x.n`. -/
  | rel (op : Fin 6)
  /-- `v.f = value`. -/
  | flag (inner : Bool) (value : Bool)
  | and (left right : Body)
  | or (left right : Body)
  | not (arg : Body)
  /-- An inner quantifier over kind `b` if `kindB`, else `a`. Inside another it is its body. -/
  | quant (universal kindB : Bool) (body : Body)
  deriving Repr

structure Requirement where
  universal : Bool
  kindB : Bool
  body : Body
  deriving Repr

structure Contract where
  requires : List Requirement
  /-- The conflict policy: `source-order` if set, else `unknown`. -/
  sourceOrder : Bool
  /-- Whether both kinds accept `s1` and `s2`, or `s1` alone. -/
  twoSources : Bool
  deriving Repr

/-- A fact. `kind` is `a`, `b` or the undeclared `z`; `source` is `s1`, `s2` or `u`, which no
    contract accepts. -/
structure Fact where
  kind : Fin 3
  source : Fin 3
  key : Nat
  n : Option Int
  f : Option Bool
  deriving Repr, DecidableEq

structure Environment where
  facts : List Fact
  /-- Completeness statements: the kind (`b` if set) and the source. -/
  complete : List (Bool × Fin 3)
  deriving Repr

structure Case where
  contract : Contract
  env : Environment
  deriving Repr

def kindName (kindB : Bool) : String := if kindB then "b" else "a"
def factKind (f : Fact) : String := ["a", "b", "z"][f.kind.val]!
def sourceName (s : Fin 3) : String := ["s1", "s2", "u"][s.val]!
def accepted (c : Contract) : List String := if c.twoSources then ["s1", "s2"] else ["s1"]
def opOf (i : Fin 6) : Op :=
  match i.val with
  | 0 => .eq | 1 => .ne | 2 => .lt | 3 => .le | 4 => .gt | _ => .ge
def opCode (i : Fin 6) : String := ["eq", "ne", "lt", "le", "gt", "ge"][i.val]!

/-! ## The wire format -/

private def obj (members : List (String × Json)) : Json := Json.mkObj members
private def field (var name : String) : Json := obj [("field", name), ("var", var)]
private def intTy : Json := obj [("type", "int")]
private def boolTy : Json := obj [("type", "bool")]
private def cmp (op : String) (left right : Json) : Json :=
  obj [("cmp", op), ("left", left), ("right", right)]

def Body.json (bound : Bool) : Body → Json
  | .num op inner lit =>
    cmp (opCode op) (field (if inner && bound then "y" else "x") "n")
      (obj [("lit", toString lit), ("of", intTy)])
  | .rel op => cmp (opCode op) (field "x" "n") (field (if bound then "y" else "x") "n")
  | .flag inner value =>
    cmp "eq" (field (if inner && bound then "y" else "x") "f") (obj [("lit", value), ("of", boolTy)])
  | .and l r => obj [("and", Json.arr #[l.json bound, r.json bound])]
  | .or l r => obj [("or", Json.arr #[l.json bound, r.json bound])]
  | .not b => obj [("not", b.json bound)]
  | .quant universal kindB body =>
    if bound then body.json true
    else if universal then
      obj [("forall", "y"), ("in", kindName kindB), ("holds", body.json true)]
    else obj [("exists", "y"), ("in", kindName kindB), ("where", body.json true)]

def Requirement.json (r : Requirement) : Json :=
  if r.universal then
    obj [("forall", "x"), ("in", kindName r.kindB), ("holds", r.body.json false)]
  else obj [("exists", "x"), ("in", kindName r.kindB), ("where", r.body.json false)]

private def digits (i : Nat) : String := if i < 10 then s!"0{i}" else toString i

def Contract.json (c : Contract) : Json :=
  let kind := obj [
    ("fields", obj [
      ("f", obj [("optional", true), ("type", "bool")]),
      ("id", obj [("type", "text")]),
      ("n", obj [("optional", true), ("type", "int")])]),
    ("key", Json.arr #["id"])]
  let sources := Json.arr ((accepted c).map Json.str).toArray
  obj [
    ("evaluation", obj [("semantics", "kleene-1")]),
    ("evidence", obj [
      ("conflicts", if c.sourceOrder then "source-order" else "unknown"),
      ("sources", obj [("a", sources), ("b", sources)])]),
    ("identity", obj [("id", "generated"), ("version", "1")]),
    ("inputs", obj []),
    ("kinds", obj [("a", kind), ("b", kind)]),
    ("language", "work-contract-1"),
    ("policy", obj []),
    ("requires", Json.arr (c.requires.zipIdx.map fun (r, i) =>
      obj [("id", s!"R{digits i}"), ("predicate", r.json)]).toArray)]

def Fact.fields (f : Fact) : List (String × Json) :=
  [("id", Json.str s!"k{f.key}")] ++
    (match f.n with | some n => [("n", Json.str (toString n))] | none => []) ++
    (match f.f with | some b => [("f", Json.bool b)] | none => [])

def Environment.json (e : Environment) : Json :=
  let complete := (e.complete.map fun (kindB, s) => (kindName kindB, sourceName s)).eraseDups
  let sorted := complete.toArray.qsort fun a b => a.1 < b.1 || (a.1 == b.1 && a.2 < b.2)
  obj [
    ("complete", Json.arr (sorted.map fun (kind, source) =>
      obj [("asOf", "0"), ("kind", kind), ("source", source)])),
    ("facts", Json.arr (e.facts.zipIdx.map fun (f, i) =>
      obj [("fields", obj f.fields), ("id", s!"f{digits i}"), ("kind", factKind f),
        ("source", sourceName f.source)]).toArray),
    ("inputs", obj [])]

/-! ## The same case as terms of the semantic definition -/

def Body.pred (bound : Bool) : Body → Pred
  | .num op inner lit =>
    .cmp (opOf op) (.field (if inner && bound then "y" else "x") "n") (.lit .int (.num lit))
  | .rel op => .cmp (opOf op) (.field "x" "n") (.field (if bound then "y" else "x") "n")
  | .flag inner value =>
    .cmp .eq (.field (if inner && bound then "y" else "x") "f") (.lit .bool (.bool value))
  | .and l r => .and (l.pred bound) (r.pred bound)
  | .or l r => .or (l.pred bound) (r.pred bound)
  | .not b => .not (b.pred bound)
  | .quant universal kindB body =>
    if bound then body.pred true
    else if universal then .all "y" (kindName kindB) (body.pred true)
    else .ex "y" (kindName kindB) (body.pred true)

def Requirement.pred (r : Requirement) : Pred :=
  if r.universal then .all "x" (kindName r.kindB) (r.body.pred false)
  else .ex "x" (kindName r.kindB) (r.body.pred false)

def Fact.record (f : Fact) : Record :=
  ⟨[("id", .text s!"k{f.key}")] ++
    (match f.n with | some n => [("n", Value.num n)] | none => []) ++
    (match f.f with | some b => [("f", Value.bool b)] | none => [])⟩

/-- Whether a contract accepts a fact: a declared kind from an accepted source. -/
def Fact.counts (c : Contract) (f : Fact) : Bool :=
  f.kind.val < 2 && (accepted c).contains (sourceName f.source)

/-- The settled environment of a case **in which no two accepted facts of a kind share a key**:
    the accepted facts as records, and a kind closed when an accepted source declared it complete.
    This is written from the specification (section 7, steps 2 and 6), not from the evaluator. -/
def Case.settled (c : Case) : Env where
  inputs := fun _ => none
  params := fun _ => none
  records := fun kind =>
    (c.env.facts.filter fun f => f.counts c.contract && factKind f == kind).map (·.record)
  closed := fun kind =>
    c.env.complete.any fun (kindB, s) =>
      kindName kindB == kind && (accepted c.contract).contains (sourceName s)

/-- Whether no two accepted facts of one kind share a key. -/
def Case.keysDistinct (c : Case) : Bool :=
  let keys := (c.env.facts.filter (·.counts c.contract)).map fun f => (f.kind.val, f.key)
  keys.eraseDups.length == keys.length

/-! ## Generators and shrinking -/

private def genBool : Gen Bool := Gen.chooseAny Bool
private def genFin (n : Nat) : Gen (Fin (n + 1)) := do
  let k ← Gen.choose Nat 0 n (by omega)
  pure (Fin.ofNat _ k.val)
private def genLit : Gen Int := do
  let k ← Gen.choose Nat 0 3 (by omega)
  pure (Int.ofNat k.val - 1)

def genBody : Nat → Bool → Gen Body
  | 0, bound => do
    match (← Gen.choose Nat 0 2 (by omega)).val with
    | 0 => pure (.num (← genFin 5) (bound && (← genBool)) (← genLit))
    | 1 => if bound then pure (.rel (← genFin 5)) else pure (.flag false (← genBool))
    | _ => pure (.flag (bound && (← genBool)) (← genBool))
  | fuel + 1, bound => do
    match (← Gen.choose Nat 0 5 (by omega)).val with
    | 0 => pure (.and (← genBody fuel bound) (← genBody fuel bound))
    | 1 => pure (.or (← genBody fuel bound) (← genBody fuel bound))
    | 2 => pure (.not (← genBody fuel bound))
    | 3 =>
      if bound then genBody fuel bound
      else pure (.quant (← genBool) (← genBool) (← genBody fuel true))
    | _ => genBody 0 bound

def genRequirement : Gen Requirement := do
  pure ⟨← genBool, ← genBool, ← genBody 3 false⟩

def genContract : Gen Contract := do
  let count := (← Gen.choose Nat 1 3 (by omega)).val
  let requires ← (List.range count).mapM fun _ => genRequirement
  pure ⟨requires, ← genBool, ← genBool⟩

def genFact : Gen Fact := do
  -- Mostly declared kinds and accepted sources, so that most facts take part in evaluation.
  let kind := match (← Gen.choose Nat 0 6 (by omega)).val with | 6 => 2 | k => Fin.ofNat _ (k % 2)
  let source := match (← Gen.choose Nat 0 6 (by omega)).val with | 6 => 2 | k => Fin.ofNat _ (k % 2)
  let key := (← Gen.choose Nat 0 2 (by omega)).val
  let n ← if ← genBool then pure (some (← genLit)) else pure none
  let f ← if ← genBool then pure (some (← genBool)) else pure none
  pure ⟨kind, source, key, n, f⟩

def genEnvironment : Gen Environment := do
  let count := (← Gen.choose Nat 0 5 (by omega)).val
  let facts ← (List.range count).mapM fun _ => genFact
  let statements := (← Gen.choose Nat 0 3 (by omega)).val
  let complete ← (List.range statements).mapM fun _ => do pure (← genBool, ← genFin 2)
  pure ⟨facts, complete⟩

def genCase : Gen Case := do pure ⟨← genContract, ← genEnvironment⟩

def Body.shrink : Body → List Body
  | .and l r => [l, r] ++ (l.shrink.map (.and · r)) ++ (r.shrink.map (.and l ·))
  | .or l r => [l, r] ++ (l.shrink.map (.or · r)) ++ (r.shrink.map (.or l ·))
  | .not b => b :: b.shrink.map .not
  | .quant u k b => b :: b.shrink.map (.quant u k ·)
  | .num op inner lit => if lit == 0 then [] else [.num op inner 0]
  | _ => []

/-- Every way of removing one element, then every way of shrinking one. -/
def shrinkList {α : Type} (shrink : α → List α) : List α → List (List α)
  | [] => []
  | x :: xs =>
    [xs] ++ ((shrink x).map (· :: xs)) ++ ((shrinkList shrink xs).map (x :: ·))

def Fact.shrink (f : Fact) : List Fact :=
  (if f.n.isSome then [{ f with n := none }] else []) ++
  (if f.f.isSome then [{ f with f := none }] else []) ++
  (if f.key != 0 then [{ f with key := 0 }] else [])

instance : Shrinkable Case where
  shrink c :=
    ((shrinkList Fact.shrink c.env.facts).map fun facts => { c with env.facts := facts }) ++
    ((shrinkList (fun _ => []) c.env.complete).map fun complete =>
      { c with env.complete := complete }) ++
    (((shrinkList (fun (r : Requirement) => r.body.shrink.map fun b => { r with body := b })
      c.contract.requires).filter (!·.isEmpty)).map fun requires =>
        { c with contract.requires := requires })

instance : Arbitrary Case where
  arbitrary := genCase

instance : Shrinkable Fact where
  shrink := Fact.shrink

instance : Arbitrary Fact where
  arbitrary := genFact

end Generated

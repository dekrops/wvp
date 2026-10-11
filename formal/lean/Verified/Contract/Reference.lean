import Lean.Data.Json
import Verified.Contract.Semantics

/-!
The reference evaluator: Work Contract Language 1 from JSON to a decision.

`Semantics.lean` is the definition of evaluation and is what the theorems are about. This file
is everything around it that the specification also fixes (sections 2 to 8): reading a contract
and an environment, the static rules, acceptance by source, conformance, conflict resolution
and closed kinds. It calls `Pred.eval` for the requirements themselves.

Nothing in this file is proved. It is a second implementation, written from the specification,
whose agreement with the Scala evaluator on the shared corpus is checked in CI.
-/

namespace Verified.Contract.Reference

open Lean (Json)

inductive Refusal where
  | contractMalformed | contractIllFormed | environmentMalformed | environmentNonconforming
  | workLimit

def Refusal.code : Refusal → String
  | .contractMalformed => "CONTRACT_MALFORMED"
  | .contractIllFormed => "CONTRACT_ILL_FORMED"
  | .environmentMalformed => "ENVIRONMENT_MALFORMED"
  | .environmentNonconforming => "ENVIRONMENT_NONCONFORMING"
  | .workLimit => "WORK_LIMIT"

/-- The wire form of a predicate: `and` and `or` take lists. -/
inductive WPred where
  | cmp (op : Op) (left right : Term)
  | and (args : List WPred)
  | or (args : List WPred)
  | not (arg : WPred)
  | ex (var kind : String) (body : WPred)
  | all (var kind : String) (body : WPred)

structure FieldTy where
  ty : Ty
  optional : Bool

structure KindDecl where
  key : List String
  fields : List (String × FieldTy)

structure ParamDecl where
  policyId : String
  policyVersion : String
  ty : Ty
  value : Value

structure Doc where
  language : String
  id : String
  version : String
  inputs : List (String × Ty)
  kinds : List (String × KindDecl)
  conflicts : String
  sources : List (String × List String)
  policy : List (String × ParamDecl)
  semantics : String
  cutoff : Option String
  requires : List (String × WPred)

/-! ## Lexical rules (specification, section 3) -/

private def alpha (c : Char) : Bool := ('a' ≤ c ∧ c ≤ 'z') ∨ ('A' ≤ c ∧ c ≤ 'Z')
private def digit (c : Char) : Bool := '0' ≤ c ∧ c ≤ '9'

def validName (s : String) : Bool :=
  match s.toList with
  | [] => false
  | first :: rest =>
    alpha first && rest.length ≤ 63 &&
      rest.all fun c => alpha c || digit c || c == '_' || c == '.' || c == '-'

def validVersion (s : String) : Bool :=
  match s.toList with
  | [] => false
  | first :: rest =>
    (alpha first || digit first) && rest.length ≤ 63 &&
      rest.all fun c => alpha c || digit c || c == '.' || c == '+' || c == '-'

def validCurrency (s : String) : Bool :=
  s.length == 3 && s.toList.all fun c => 'A' ≤ c ∧ c ≤ 'Z'

private def bound : Int := 9223372036854775808

/-- A number: `-?(0|[1-9][0-9]{0,18})`, not `-0`, strictly inside ±2^63. -/
def number (s : String) : Option Int :=
  let (negative, digits) :=
    match s.toList with
    | '-' :: rest => (true, rest)
    | all => (false, all)
  let shaped :=
    match digits with
    | [] => false
    | ['0'] => !negative
    | first :: rest => first != '0' && digit first && rest.length ≤ 18 && rest.all digit
  if shaped then
    let magnitude : Int := digits.foldl (fun acc c => acc * 10 + (c.toNat - '0'.toNat)) 0
    let value := if negative then -magnitude else magnitude
    if -bound < value ∧ value < bound then some value else none
  else none

def validText (s : String) : Bool := s.utf8ByteSize ≤ 1024

/-! ## Reading JSON, strictly -/

private def entries : Json → Option (List (String × Json))
  | .obj kvs => some kvs.toList
  | _ => none

private def str : Json → Option String
  | .str s => some s
  | _ => none

private def arr : Json → Option (List Json)
  | .arr values => some values.toList
  | _ => none

/-- A JSON number that is a whole number within the 32-bit range. -/
private def small : Json → Option Int
  | .num n =>
    let scale : Int := (10 : Int) ^ n.exponent
    if n.mantissa % scale == 0 then
      let value := n.mantissa / scale
      if -2147483648 ≤ value ∧ value ≤ 2147483647 then some value else none
    else none
  | _ => none

private def member (fields : List (String × Json)) (name : String) : Option Json :=
  fields.lookup name

private def only (fields : List (String × Json)) (allowed : List String) : Bool :=
  fields.all fun (name, _) => allowed.contains name

private def exactly (fields : List (String × Json)) (names : List String) : Bool :=
  fields.length == names.length && names.all fun name => (fields.lookup name).isSome

private def each {α β : Type} (f : α → Option β) : List α → Option (List β)
  | [] => some []
  | head :: tail => do
    let h ← f head
    let t ← each f tail
    pure (h :: t)

private def table {β : Type} (f : Json → Option β) (j : Json) : Option (List (String × β)) := do
  let fields ← entries j
  each (fun (name, value) => (f value).map fun v => (name, v)) fields

/-- A type, with the members allowed beside its own. -/
private def readTy (fields : List (String × Json)) (extra : List String) : Option Ty := do
  let name ← (member fields "type").bind str
  match name with
  | "text" => if only fields ("type" :: extra) then some .text else none
  | "bool" => if only fields ("type" :: extra) then some .bool else none
  | "int" => if only fields ("type" :: extra) then some .int else none
  | "time" => if only fields ("type" :: extra) then some .time else none
  | "decimal" =>
    if only fields ("type" :: "scale" :: extra) then do
      let scale ← (member fields "scale").bind small
      -- Out-of-range scales are a static error, not a reading error: keep them representable.
      pure (.decimal scale.toNat |> fun ty => if scale < 0 then .decimal 99 else ty)
    else none
  | "money" =>
    if only fields ("type" :: "scale" :: "currency" :: extra) then do
      let scale ← (member fields "scale").bind small
      let currency ← (member fields "currency").bind str
      pure (if scale < 0 then .money currency 99 else .money currency scale.toNat)
    else none
  | _ => none

private def ty (j : Json) : Option Ty := (entries j).bind (readTy · [])

private def fieldTy (j : Json) : Option FieldTy := do
  let fields ← entries j
  let t ← readTy fields ["optional"]
  match member fields "optional" with
  | none => pure ⟨t, false⟩
  | some (.bool true) => pure ⟨t, true⟩
  | some _ => none

/-- A value written next to its type. -/
def value (t : Ty) (j : Json) : Option Value :=
  match t, j with
  | .text, .str s => if validText s then some (.text s) else none
  | .bool, .bool b => some (.bool b)
  | .text, _ => none
  | .bool, _ => none
  | .time, .str s => (number s).bind fun n => if n ≥ 0 then some (.num n) else none
  | _, .str s => (number s).map .num
  | _, _ => none

private def term (j : Json) : Option Term := do
  let fields ← entries j
  if exactly fields ["lit", "of"] then do
    let t ← (member fields "of").bind ty
    let v ← (member fields "lit").bind (value t)
    pure (.lit t v)
  else if exactly fields ["input"] then (member fields "input").bind str |>.map .input
  else if exactly fields ["param"] then (member fields "param").bind str |>.map .param
  else if exactly fields ["var", "field"] then do
    let v ← (member fields "var").bind str
    let f ← (member fields "field").bind str
    pure (.field v f)
  else none

private def op : String → Option Op
  | "eq" => some .eq | "ne" => some .ne | "lt" => some .lt
  | "le" => some .le | "gt" => some .gt | "ge" => some .ge
  | _ => none

/-- Nesting is bounded while reading, as in the other implementation. -/
private partial def pred (depth : Nat) (j : Json) : Option WPred :=
  if depth > 64 then none
  else do
    let fields ← entries j
    if exactly fields ["cmp", "left", "right"] then do
      let o ← (member fields "cmp").bind str |>.bind op
      let l ← (member fields "left").bind term
      let r ← (member fields "right").bind term
      pure (.cmp o l r)
    else if exactly fields ["and"] then
      (member fields "and").bind arr |>.bind (each (pred (depth + 1))) |>.map .and
    else if exactly fields ["or"] then
      (member fields "or").bind arr |>.bind (each (pred (depth + 1))) |>.map .or
    else if exactly fields ["not"] then (member fields "not").bind (pred (depth + 1)) |>.map .not
    else if exactly fields ["exists", "in", "where"] then do
      let v ← (member fields "exists").bind str
      let k ← (member fields "in").bind str
      let b ← (member fields "where").bind (pred (depth + 1))
      pure (.ex v k b)
    else if exactly fields ["forall", "in", "holds"] then do
      let v ← (member fields "forall").bind str
      let k ← (member fields "in").bind str
      let b ← (member fields "holds").bind (pred (depth + 1))
      pure (.all v k b)
    else none

private def strings (j : Json) : Option (List String) := (arr j).bind (each str)

private def kind (j : Json) : Option KindDecl := do
  let fields ← entries j
  if !only fields ["key", "fields"] then none
  let key ← (member fields "key").bind strings
  let declared ← (member fields "fields").bind (table fieldTy)
  pure ⟨key, declared⟩

private def param (j : Json) : Option ParamDecl := do
  let fields ← entries j
  if !only fields ["policy", "type", "value"] then none
  let policy ← (member fields "policy").bind entries
  if !only policy ["id", "version"] then none
  let id ← (member policy "id").bind str
  let version ← (member policy "version").bind str
  let t ← (member fields "type").bind ty
  let v ← (member fields "value").bind (value t)
  pure ⟨id, version, t, v⟩

private def requirement (j : Json) : Option (String × WPred) := do
  let fields ← entries j
  if !only fields ["id", "predicate"] then none
  let id ← (member fields "id").bind str
  let p ← (member fields "predicate").bind (pred 0)
  pure (id, p)

def contract (j : Json) : Option Doc := do
  let fields ← entries j
  if !only fields
      ["language", "identity", "inputs", "kinds", "evidence", "policy", "evaluation", "requires"]
  then none
  let language ← (member fields "language").bind str
  let identity ← (member fields "identity").bind entries
  if !only identity ["id", "version"] then none
  let id ← (member identity "id").bind str
  let version ← (member identity "version").bind str
  let inputs ← (member fields "inputs").bind (table ty)
  let kinds ← (member fields "kinds").bind (table kind)
  let evidence ← (member fields "evidence").bind entries
  if !only evidence ["conflicts", "sources"] then none
  let conflicts ← (member evidence "conflicts").bind str
  if conflicts != "unknown" && conflicts != "source-order" then none
  let sources ← (member evidence "sources").bind (table strings)
  let policy ← (member fields "policy").bind (table param)
  let evaluation ← (member fields "evaluation").bind entries
  if !only evaluation ["semantics", "cutoff"] then none
  let semantics ← (member evaluation "semantics").bind str
  let cutoff ← match member evaluation "cutoff" with
    | none => some none
    | some (.str name) => some (some name)
    | some _ => none
  let requires ← (member fields "requires").bind arr |>.bind (each requirement)
  pure ⟨language, id, version, inputs, kinds, conflicts, sources, policy, semantics, cutoff,
    requires⟩

/-! ## Static rules (specification, section 5) -/

private partial def nodes : WPred → Nat
  | .cmp .. => 1
  | .and args => 1 + (args.map nodes).foldl (· + ·) 0
  | .or args => 1 + (args.map nodes).foldl (· + ·) 0
  | .not arg => 1 + nodes arg
  | .ex _ _ body => 1 + nodes body
  | .all _ _ body => 1 + nodes body

private partial def depth : WPred → Nat
  | .cmp .. => 0
  | .and args => (args.map depth).foldl max 0
  | .or args => (args.map depth).foldl max 0
  | .not arg => depth arg
  | .ex _ _ body => 1 + depth body
  | .all _ _ body => 1 + depth body

private partial def same : WPred → WPred → Bool
  | .cmp o l r, .cmp o' l' r' => o == o' && l == l' && r == r'
  | .and a, .and b => a.length == b.length && (a.zip b).all fun (x, y) => same x y
  | .or a, .or b => a.length == b.length && (a.zip b).all fun (x, y) => same x y
  | .not a, .not b => same a b
  | .ex v k a, .ex v' k' b => v == v' && k == k' && same a b
  | .all v k a, .all v' k' b => v == v' && k == k' && same a b
  | _, _ => false

private def validTy : Ty → Bool
  | .decimal scale => scale ≤ 18
  | .money currency scale => validCurrency currency && scale ≤ 18
  | _ => true

private def ordered : Ty → Bool
  | .text | .bool => false
  | _ => true

private def distinct (names : List String) : Bool := names.eraseDups.length == names.length

private def ascending (names : List String) : Bool :=
  match names with
  | [] => true
  | _ :: rest => (names.zip rest).all fun (a, b) => a < b

private def termTy (doc : Doc) (scope : List (String × String)) : Term → Option Ty
  | .lit t _ => if validTy t then some t else none
  | .input name => doc.inputs.lookup name
  | .param name => (doc.policy.lookup name).map (·.ty)
  | .field var name => do
    let kindName ← scope.lookup var
    let declared ← doc.kinds.lookup kindName
    (declared.fields.lookup name).map (·.ty)

private partial def typed (doc : Doc) (scope : List (String × String)) : WPred → Bool
  | .cmp o left right =>
    match termTy doc scope left, termTy doc scope right with
    | some a, some b => a == b && (!(o != .eq && o != .ne) || ordered a)
    | _, _ => false
  | .and args => !args.isEmpty && args.all (typed doc scope)
  | .or args => !args.isEmpty && args.all (typed doc scope)
  | .not arg => typed doc scope arg
  | .ex var kindName body =>
    validName var && (scope.lookup var).isNone && (doc.kinds.lookup kindName).isSome &&
      typed doc ((var, kindName) :: scope) body
  | .all var kindName body =>
    validName var && (scope.lookup var).isNone && (doc.kinds.lookup kindName).isSome &&
      typed doc ((var, kindName) :: scope) body

/-- A conjunction that contains a predicate and its negation, anywhere. -/
private partial def contradictory : WPred → Bool
  | .cmp .. => false
  | .and args =>
    (args.any fun arg => match arg with
      | .not inner => args.any (same inner)
      | _ => false) || args.any contradictory
  | .or args => args.any contradictory
  | .not arg => contradictory arg
  | .ex _ _ body => contradictory body
  | .all _ _ body => contradictory body

def wellFormed (doc : Doc) : Bool :=
  let names (l : List String) := l.all validName
  let shaped :=
    doc.language == "work-contract-1" && doc.semantics == "kleene-1" &&
    validName doc.id && validVersion doc.version &&
    doc.kinds.length ≤ 32 && !doc.requires.isEmpty && doc.requires.length ≤ 64 &&
    names (doc.inputs.map (·.1)) && names (doc.kinds.map (·.1)) &&
    names (doc.policy.map (·.1)) && names (doc.requires.map (·.1)) &&
    doc.inputs.all (fun (name, _) => (doc.policy.lookup name).isNone) &&
    doc.inputs.all (fun (_, t) => validTy t) &&
    doc.kinds.all (fun (_, k) =>
      names (k.fields.map (·.1)) && k.fields.all (fun (_, f) => validTy f.ty) &&
      !k.fields.isEmpty && k.fields.length ≤ 32 && !k.key.isEmpty && distinct k.key &&
      k.key.all fun field => match k.fields.lookup field with
        | some f => !f.optional
        | none => false) &&
    doc.kinds.all (fun (name, _) => match doc.sources.lookup name with
      | some list => !list.isEmpty && names list && distinct list
      | none => false) &&
    doc.sources.all (fun (name, _) => (doc.kinds.lookup name).isSome) &&
    doc.policy.all (fun (_, p) =>
      validTy p.ty && validName p.policyId && validVersion p.policyVersion) &&
    (match doc.cutoff with
      | none => true
      | some name => doc.inputs.lookup name == some Ty.time) &&
    ascending (doc.requires.map (·.1)) &&
    (doc.requires.map fun (_, p) => nodes p).foldl (· + ·) 0 ≤ 512 &&
    doc.requires.all (fun (_, p) => depth p ≤ 3)
  shaped && doc.requires.all (fun (_, p) => typed doc [] p) &&
    !doc.requires.any (fun (_, p) => contradictory p) &&
    !doc.requires.any (fun (_, p) => match p with
      | .not inner => doc.requires.any fun (_, q) => same inner q
      | _ => false)

instance : Inhabited Pred := ⟨.cmp .eq (.input "") (.input "")⟩

/-- The wire form to the defined form: a list becomes nested binary connectives. The static
    rules guarantee the lists are not empty. -/
partial def lower : WPred → Pred
  | .cmp o l r => .cmp o l r
  | .and args => match args.map lower with
    | [] => .cmp .eq (.lit .bool (.bool true)) (.lit .bool (.bool true))
    | first :: rest => rest.foldl .and first
  | .or args => match args.map lower with
    | [] => .cmp .eq (.lit .bool (.bool true)) (.lit .bool (.bool false))
    | first :: rest => rest.foldl .or first
  | .not arg => .not (lower arg)
  | .ex v k body => .ex v k (lower body)
  | .all v k body => .all v k (lower body)

/-! ## Environment (specification, sections 6 and 7) -/

structure RawFact where
  id : String
  kind : String
  source : String
  fields : List (String × Json)

structure Complete where
  kind : String
  source : String
  asOf : Int

structure RawEnv where
  inputs : List (String × Json)
  facts : List RawFact
  complete : List Complete

private def pairsAscending (pairs : List (String × String)) : Bool :=
  match pairs with
  | [] => true
  | _ :: rest => (pairs.zip rest).all fun (a, b) => a.1 < b.1 || (a.1 == b.1 && a.2 < b.2)

def environment (j : Json) : Option RawEnv := do
  let fields ← entries j
  if !exactly fields ["inputs", "facts", "complete"] then none
  let inputs ← (member fields "inputs").bind entries
  let facts ← (member fields "facts").bind arr |>.bind (each fun fact => do
    let f ← entries fact
    if !exactly f ["id", "kind", "source", "fields"] then none
    let id ← (member f "id").bind str
    let kindName ← (member f "kind").bind str
    let source ← (member f "source").bind str
    let values ← (member f "fields").bind entries
    pure (⟨id, kindName, source, values⟩ : RawFact))
  let complete ← (member fields "complete").bind arr |>.bind (each fun statement => do
    let c ← entries statement
    if !exactly c ["kind", "source", "asOf"] then none
    let kindName ← (member c "kind").bind str
    let source ← (member c "source").bind str
    let asOf ← (member c "asOf").bind str |>.bind number
    if asOf < 0 then none
    pure (⟨kindName, source, asOf⟩ : Complete))
  if facts.length > 10000 then none
  if !inputs.all (fun (name, _) => validName name) then none
  if !facts.all (fun f => validName f.id && validName f.kind && validName f.source &&
      f.fields.all fun (name, _) => validName name) then none
  if !ascending (facts.map (·.id)) then none
  if !complete.all (fun c => validName c.kind && validName c.source) then none
  if !pairsAscending (complete.map fun c => (c.kind, c.source)) then none
  pure ⟨inputs, facts, complete⟩

structure Accepted where
  id : String
  source : String
  record : Record

structure Conflict where
  kind : String
  facts : List String
  resolvedTo : Option String

structure Outcome where
  decision : Decision
  requirements : List (String × Truth)
  ignored : List String
  conflicts : List Conflict

private def accepts (doc : Doc) (kindName source : String) : Bool :=
  match doc.sources.lookup kindName with
  | some list => list.contains source
  | none => false

private def conformingInputs (doc : Doc) (raw : RawEnv) : Option (List (String × Value)) :=
  if raw.inputs.length != doc.inputs.length then none
  else each (fun (name, t) => do
    let j ← raw.inputs.lookup name
    let v ← value t j
    pure (name, v)) doc.inputs

private def conformingFact (declared : KindDecl) (fact : RawFact) : Option Accepted := do
  let values ← each (fun (name, j) => do
    let f ← declared.fields.lookup name
    let v ← value f.ty j
    pure (name, v)) fact.fields
  if declared.fields.all (fun (name, f) => f.optional || (fact.fields.lookup name).isSome) then
    pure ⟨fact.id, fact.source, ⟨values⟩⟩
  else none

/-- Two records carry the same fields with the same values, in any order. -/
private def agree (a b : Record) : Bool :=
  a.fields.length == b.fields.length &&
    a.fields.all fun (name, v) => b.get name == some v

private def allAgree : List Accepted → Bool
  | [] => true
  | first :: rest => rest.all fun other => agree first.record other.record

private def keyOf (declared : KindDecl) (a : Accepted) : List (Option Value) :=
  declared.key.map a.record.get

/-- Groups in order of their first (lowest) identifier; members in identifier order. -/
private def groups (declared : KindDecl) (records : List Accepted) : List (List Accepted) :=
  records.foldl (fun acc record =>
    if acc.any (fun group => group.any fun other => keyOf declared other == keyOf declared record)
    then acc.map fun group =>
      if group.any (fun other => keyOf declared other == keyOf declared record)
      then group ++ [record] else group
    else acc ++ [[record]]) []

private def settle (doc : Doc) (kindName : String) (group : List Accepted) :
    Option Accepted × Option Conflict :=
  if allAgree group then (group.head?, none)
  else
    let preferred : Option Accepted :=
      if doc.conflicts == "source-order" then
        match doc.sources.lookup kindName with
        | some order =>
          match order.find? (fun source => group.any (·.source == source)) with
          | some source =>
            let fromSource := group.filter (·.source == source)
            if allAgree fromSource then fromSource.head? else none
          | none => none
        | none => none
      else none
    (preferred, some ⟨kindName, group.map (·.id), preferred.map (·.id)⟩)

private def sortByName {α : Type} (items : List (String × α)) : List (String × α) :=
  (items.toArray.qsort fun a b => a.1 < b.1).toList

def evaluateDoc (doc : Doc) (raw : RawEnv) : Except Refusal Outcome := do
  let inputs ← match conformingInputs doc raw with
    | some values => pure values
    | none => throw .environmentNonconforming
  let usable := raw.facts.filter fun f => accepts doc f.kind f.source
  let ignored := (raw.facts.filter fun f => !accepts doc f.kind f.source).map (·.id)
  let records ← match each (fun (f : RawFact) => do
      let declared ← doc.kinds.lookup f.kind
      let a ← conformingFact declared f
      pure (f.kind, a)) usable with
    | some values => pure values
    | none => throw .environmentNonconforming
  let preds := doc.requires.map fun (id, p) => (id, p)
  let size := (preds.map fun (_, p) => nodes p).foldl (· + ·) 0
  let deepest := (preds.map fun (_, p) => depth p).foldl max 0
  if size * (max raw.facts.length 1) ^ deepest > 10000000 then throw .workLimit
  let perKind := sortByName (doc.kinds.map fun (name, declared) =>
    (name, (declared, (records.filter (·.1 == name)).map (·.2))))
  let settled := perKind.map fun (name, (declared, list)) =>
    (name, (groups declared list).map (settle doc name))
  let conflicts := settled.flatMap fun (_, outcomes) => outcomes.filterMap (·.2)
  let disputed := (conflicts.filter (·.resolvedTo.isNone)).map (·.kind)
  let cutoff : Option Int := doc.cutoff.bind fun name =>
    match inputs.lookup name with
    | some (.num n) => some n
    | _ => none
  let closedKinds := (raw.complete.filter fun c =>
    accepts doc c.kind c.source && (match cutoff with
      | some at_ => c.asOf ≥ at_
      | none => true)).map (·.kind)
  let env : Env := {
    inputs := fun name => inputs.lookup name
    params := fun name => (doc.policy.lookup name).map (·.value)
    records := fun name => match settled.lookup name with
      | some outcomes => (outcomes.filterMap (·.1)).map (·.record)
      | none => []
    closed := fun name => closedKinds.contains name && !disputed.contains name
  }
  let values := preds.map fun (id, p) => (id, (lower p).eval env [])
  pure ⟨decide (values.map (·.2)), values, ignored, conflicts⟩

/-! ## The exchange format -/

private def truthCode : Truth → String
  | .true => "TRUE" | .false => "FALSE" | .unknown => "UNKNOWN"

private def decisionCode : Decision → String
  | .supported => "SUPPORTED" | .contradicted => "CONTRADICTED" | .undetermined => "UNDETERMINED"

def Outcome.json (o : Outcome) : Json :=
  Json.mkObj [
    ("decision", decisionCode o.decision),
    ("requirements", Json.arr (o.requirements.map fun (id, v) =>
      Json.mkObj [("id", id), ("value", truthCode v)]).toArray),
    ("ignored", Json.arr (o.ignored.map Json.str).toArray),
    ("conflicts", Json.arr (o.conflicts.map fun c =>
      Json.mkObj ([("kind", Json.str c.kind), ("facts", Json.arr (c.facts.map Json.str).toArray)] ++
        (match c.resolvedTo with
          | some id => [("resolvedTo", Json.str id)]
          | none => []))).toArray)]

/-- A contract and an environment as JSON in; a decision or a refusal as JSON out. The checks
    are made in the order of the specification's refusal table. -/
def run (contractJson environmentJson : Json) : Json :=
  let outcome : Except Refusal Outcome := do
    let doc ← match contract contractJson with
      | some doc => pure doc
      | none => throw .contractMalformed
    if !wellFormed doc then throw .contractIllFormed
    let raw ← match environment environmentJson with
      | some raw => pure raw
      | none => throw .environmentMalformed
    evaluateDoc doc raw
  match outcome with
  | .ok o => o.json
  | .error refusal => Json.mkObj [("refused", refusal.code)]

end Verified.Contract.Reference

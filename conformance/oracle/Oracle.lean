import Verified.Contract.Reference

/-!
The oracle: a command-line interface to the reference evaluator of Work Contract Language 1.

It adds no semantics. Every result is `Verified.Contract.Reference.run` applied to a contract and
an environment; this file only reads cases and writes results. See README.md for the interface.
-/

open Lean (Json)
open Verified.Contract.Reference

namespace Oracle

/-- The version of this interface: its arguments, its output members and its exit codes. -/
def interfaceVersion : String := "1"

structure Tally where
  results : Nat := 0
  disagreements : Nat := 0
  inputErrors : Nat := 0

private def emit (members : List (String × Json)) : IO Unit :=
  IO.println (Json.mkObj members).compress

private def inputError (tally : Tally) (case : String) (error : String) : IO Tally := do
  emit [("case", case), ("outcome", "input-error"), ("error", error)]
  pure { tally with inputErrors := tally.inputErrors + 1 }

/-- One contract and one environment. `expected`, where the case states one, is compared. -/
private def evaluate (tally : Tally) (case : String) (contract : Json) (item : Json) :
    IO Tally := do
  match item.getObjVal? "environment" with
  | .error _ => inputError tally case "no `environment` member"
  | .ok environment =>
    let result := run contract environment
    match item.getObjVal? "expected" with
    | .ok expected =>
      let agrees := result.compress == expected.compress
      emit [("case", case), ("outcome", "result"), ("result", result), ("agrees", agrees)]
      pure { tally with
        results := tally.results + 1
        disagreements := tally.disagreements + (if agrees then 0 else 1) }
    | .error _ =>
      emit [("case", case), ("outcome", "result"), ("result", result)]
      pure { tally with results := tally.results + 1 }

/-- A case file's value: one case, or a contract with a list of cases. -/
private def evaluateValue (tally : Tally) (label : String) (value : Json) : IO Tally := do
  match value.getObjVal? "contract" with
  | .error _ => inputError tally label "no `contract` member"
  | .ok contract =>
    match value.getObjVal? "cases" with
    | .ok (.arr cases) =>
      let mut tally := tally
      let mut index := 0
      for item in cases do
        tally ← evaluate tally s!"{label}#{index}" contract item
        index := index + 1
      pure tally
    | .ok _ => inputError tally label "`cases` is not an array"
    | .error _ => evaluate tally label contract value

private def evaluateText (tally : Tally) (label : String) (text : String) : IO Tally :=
  match Json.parse text with
  | .ok value => evaluateValue tally label value
  | .error error => inputError tally label s!"not JSON: {error}"

private def evaluateFile (tally : Tally) (path : System.FilePath) : IO Tally := do
  evaluateText tally path.toString (← IO.FS.readFile path)

private def evaluatePath (tally : Tally) (path : System.FilePath) : IO Tally := do
  if ← path.isDir then
    let entries ← path.readDir
    let files := (entries.map (·.path)).filter (·.extension == some "json")
    let mut tally := tally
    for file in files.qsort (fun a b => a.toString < b.toString) do
      tally ← evaluateFile tally file
    pure tally
  else evaluateFile tally path

/-- One case file's value on each line of standard input. Empty lines are skipped. -/
private partial def evaluateLines (stream : IO.FS.Stream) (tally : Tally) (number : Nat) :
    IO Tally := do
  let line ← stream.getLine
  if line.isEmpty then pure tally
  else if line.trim.isEmpty then evaluateLines stream tally (number + 1)
  else evaluateLines stream (← evaluateText tally s!"stdin:{number}" line) (number + 1)

/-- Every case of every path, or of standard input. `none` if the command could not run. -/
def evaluateAll (paths : List String) : IO (Option Tally) := do
  try
    if paths.isEmpty then
      pure (some (← evaluateLines (← IO.getStdin) {} 1))
    else
      pure (some (← paths.foldlM (fun tally path => evaluatePath tally (System.FilePath.mk path)) ({} : Tally)))
  catch error =>
    IO.eprintln s!"wvp-oracle: {error}"
    pure none

def usage : String :=
  "Usage: wvp-oracle evaluate [PATH ...]\n" ++
  "       wvp-oracle version\n" ++
  "\n" ++
  "evaluate  Evaluate Work Contract Language 1 cases with the Lean reference evaluator.\n" ++
  "          PATH is a case file or a directory of case files. With no PATH, each line of\n" ++
  "          standard input is one case file's JSON. One line of JSON is written per case.\n" ++
  "\n" ++
  "Exit codes: 0 every case has a result, and agrees with its `expected` where it has one;\n" ++
  "            1 a result disagrees with `expected`; 2 a case could not be read;\n" ++
  "            3 the command could not run."

end Oracle

open Oracle in
def main (args : List String) : IO UInt32 := do
  match args with
  | ["version"] =>
    IO.println (Json.mkObj [
      ("tool", "wvp-oracle"), ("interface", interfaceVersion),
      ("language", "work-contract-1"), ("semantics", "kleene-1"),
      ("lean", Lean.versionString)]).compress
    return 0
  | "evaluate" :: paths =>
    let some tally ← evaluateAll paths | return 3
    IO.eprintln s!"wvp-oracle: {tally.results} results, {tally.disagreements} disagreeing with `expected`, {tally.inputErrors} cases not read"
    if tally.inputErrors > 0 then return 2
    if tally.disagreements > 0 then return 1
    if tally.results == 0 then
      IO.eprintln "wvp-oracle: no case found"
      return 3
    return 0
  | _ =>
    IO.eprintln usage
    return 3

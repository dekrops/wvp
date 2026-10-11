import Verified.Contract.Reference

/-!
Runs the reference evaluator over conformance files and compares each outcome with the expected
one. A file is either one case (`contract`, `environment`, `expected`) or a batch
(`contract`, `cases: [{ environment, expected }]`).

    lake exe contract-reference ../../test-vectors/work-contract/v1/cases [more directories]
-/

open Lean (Json)
open Verified.Contract.Reference

private def field (j : Json) (name : String) : Except String Json := j.getObjVal? name

private def check (label : String) (contract environment expected : Json) : IO Bool := do
  let got := run contract environment
  if got.compress == expected.compress then pure true
  else
    IO.eprintln s!"MISMATCH {label}\n  expected {expected.compress}\n  got      {got.compress}"
    pure false

private def checkFile (path : System.FilePath) : IO (Nat × Nat) := do
  let text ← IO.FS.readFile path
  let json ← IO.ofExcept (Json.parse text)
  let contract ← IO.ofExcept (field json "contract")
  match field json "cases" with
  | .ok (.arr cases) =>
    let mut failed := 0
    let mut index := 0
    for item in cases do
      let environment ← IO.ofExcept (field item "environment")
      let expected ← IO.ofExcept (field item "expected")
      if !(← check s!"{path}#{index}" contract environment expected) then failed := failed + 1
      index := index + 1
    pure (cases.size, failed)
  | _ =>
    let environment ← IO.ofExcept (field json "environment")
    let expected ← IO.ofExcept (field json "expected")
    pure (1, if ← check path.toString contract environment expected then 0 else 1)

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "Usage: contract-reference <directory> [<directory> ...]"
    return 2
  let mut total := 0
  let mut failed := 0
  for directory in args do
    let entries ← System.FilePath.readDir directory
    let files := (entries.map (·.path)).filter (·.extension == some "json")
    for path in files.qsort (fun a b => a.toString < b.toString) do
      let (count, bad) ← checkFile path
      total := total + count
      failed := failed + bad
  if total == 0 then
    IO.eprintln "No cases found."
    return 2
  IO.println s!"Reference evaluator: {total - failed} of {total} cases agree with the expected outcomes."
  return (if failed == 0 then 0 else 1)

import Refinement

/-!
Checks that the evaluator's `lower`, which is `partial` and so has no equations, produces the
same term as `Refinement.lowerTotal` for every requirement of every contract in the directories
given. This is the link the theorems cannot provide. It is a test.

    wvp-lowering <directory> [<directory> ...]
-/

open Lean (Json)
open Verified.Contract.Reference

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "Usage: wvp-lowering <directory> [<directory> ...]"
    return 3
  let mut contracts := 0
  let mut requirements := 0
  let mut different := 0
  for directory in args do
    let entries ← System.FilePath.readDir directory
    let files := (entries.map (·.path)).filter (·.extension == some "json")
    for path in files.qsort (fun a b => a.toString < b.toString) do
      let json ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
      -- A file whose contract the evaluator does not read has no requirement to lower.
      let some doc := (json.getObjVal? "contract").toOption.bind contract | continue
      contracts := contracts + 1
      for (id, predicate) in doc.requires do
        requirements := requirements + 1
        -- `Pred` has no decidable equality in the published definitions. Its derived `Repr`
        -- prints every constructor and argument, so equal text is equal terms.
        if toString (repr (lower predicate)) != toString (repr (Refinement.lowerTotal predicate)) then
          different := different + 1
          IO.eprintln s!"DIFFERENT {path} {id}"
  if requirements == 0 then
    IO.eprintln "No requirement found."
    return 3
  IO.println s!"Lowering: {requirements} requirements of {contracts} contracts; the evaluator's lowering and the total one differ on {different}."
  return (if different == 0 then 0 else 1)

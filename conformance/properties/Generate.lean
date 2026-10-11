import Generated

/-!
Writes generated cases with the result the reference evaluator gives for each, in the format of
the corpus's differential batches, so that another implementation's harness can run them.

    wvp-generate <seed> <contracts> <environments-per-contract> <directory>

The output is a function of the three numbers, this package and the Lean toolchain. The cases
are not conformance vectors: the expectation in each is one implementation's result.
-/

open Lean (Json)
open Verified.Contract.Reference
open Plausible
open Generated

/-- The version of the generator: what it generates for given arguments. -/
def generatorVersion : String := "1"

private def digits4 (i : Nat) : String :=
  let s := toString i
  String.mk (List.replicate (4 - s.length) '0') ++ s

def main (args : List String) : IO UInt32 := do
  match args with
  | [seedText, contractsText, environmentsText, directory] =>
    let (some seed, some contracts, some environments) :=
        (seedText.toNat?, contractsText.toNat?, environmentsText.toNat?)
      | do IO.eprintln "wvp-generate: the first three arguments are numbers"; return 3
    let batches : Gen (List (Contract × List Environment)) :=
      (List.range contracts).mapM fun _ => do
        pure (← genContract, ← (List.range environments).mapM fun _ => genEnvironment)
    let .ok generated := (runRandWith seed batches).run ⟨10⟩
      | do IO.eprintln "wvp-generate: generation failed"; return 3
    let out : System.FilePath := directory
    IO.FS.createDirAll (out / "differential")
    let mut cases := 0
    let mut refused := 0
    for ((contract, envs), index) in generated.zipIdx do
      let items := envs.map fun env =>
        let expected := run contract.json env.json
        (Json.mkObj [("environment", env.json), ("expected", expected)], expected)
      cases := cases + items.length
      refused := refused + (items.filter fun (_, e) => (e.getObjVal? "refused").isOk).length
      IO.FS.writeFile (out / "differential" / s!"generated-{digits4 index}.json")
        ((Json.mkObj [("contract", contract.json),
          ("cases", Json.arr (items.map (·.1)).toArray)]).compress ++ "\n")
    IO.FS.writeFile (out / "manifest.json") ((Json.mkObj [
      ("generator", "wvp-generate"), ("generatorVersion", generatorVersion),
      ("seed", seed), ("contracts", contracts), ("environmentsPerContract", environments),
      ("cases", cases), ("refused", refused), ("lean", Lean.versionString),
      ("oracle", "Verified.Contract.Reference.run"),
      ("note", "Generated cases. Not conformance vectors: each expectation is the Lean reference evaluator's result.")
      ]).pretty ++ "\n")
    IO.println s!"{cases} cases for {contracts} contracts written to {directory} ({refused} refused)"
    return 0
  | _ =>
    IO.eprintln "Usage: wvp-generate <seed> <contracts> <environments-per-contract> <directory>"
    return 3

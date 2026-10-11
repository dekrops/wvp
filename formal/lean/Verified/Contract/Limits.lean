import Verified.Contract.Theorems

namespace Verified.Contract

/-!
What the theorems do not say.

`eval_monotone` and `definite_decision_is_stable` hold under `Extends`, whose last clause says a
kind declared complete gains no records. The examples here are proved, not asserted: each is a
pair of environments just outside that hypothesis in which a definite decision changes. They
exist so that the theorems cannot be read as a guarantee about evidence in general.

Two further situations are outside the model altogether, because the model's environment is the
one left after conflicts were settled: a later record that conflicts with an earlier one, and a
different cutoff. Neither is an `Extends` step. Both are described in formal/lean/README.md and
pinned by tests of the Scala evaluator.
-/

private def one : Term := .lit .int (.num 1)

/-- Every record of kind "posting" carries amount 1. -/
def everyAmountIsOne : Pred := .all "p" "posting" (.cmp .eq (.field "p" "amount") one)

/-- Some record of kind "posting" carries amount 1. -/
def someAmountIsOne : Pred := .ex "p" "posting" (.cmp .eq (.field "p" "amount") one)

def noInputs : String → Option Value := fun _ => none

/-- No postings, and the source declared that complete. -/
def declaredComplete : Env := ⟨noInputs, noInputs, fun _ => [], fun _ => true⟩

/-- The same source statement, but a posting with amount 2 turned up afterwards. -/
def lateRecord : Env :=
  ⟨noInputs, noInputs, fun _ => [⟨[("amount", .num 2)]⟩], fun _ => true⟩

/-- The same records as `declaredComplete`, with the completeness statement withdrawn. -/
def withdrawn : Env := ⟨noInputs, noInputs, fun _ => [], fun _ => false⟩

/-- If a listing declared complete was not complete, a supported decision can become
    contradicted. The later environment has every earlier record and the same inputs; it
    violates only the clause that closed kinds gain nothing. Monotonicity needs that clause. -/
theorem late_record_in_complete_listing_overturns_support :
    (∀ kind record, record ∈ declaredComplete.records kind → record ∈ lateRecord.records kind) ∧
      evaluate declaredComplete [everyAmountIsOne] = .supported ∧
      evaluate lateRecord [everyAmountIsOne] = .contradicted := by
  refine ⟨?_, ?_, ?_⟩
  · intro kind record member
    simp [declaredComplete] at member
  · decide
  · decide

/-- Likewise a contradicted decision ("there is no such posting") can become supported. -/
theorem late_record_in_complete_listing_overturns_contradiction :
    evaluate declaredComplete [someAmountIsOne] = .contradicted ∧
      evaluate ⟨noInputs, noInputs, fun _ => [⟨[("amount", .num 1)]⟩], fun _ => true⟩
        [someAmountIsOne] = .supported := by
  constructor <;> decide

/-- Withdrawing a completeness statement is not an extension: definite answers become
    undetermined. Stability runs in one direction only. -/
theorem withdrawn_completeness_loses_the_decision :
    evaluate declaredComplete [everyAmountIsOne] = .supported ∧
      evaluate withdrawn [everyAmountIsOne] = .undetermined ∧
      evaluate declaredComplete [someAmountIsOne] = .contradicted ∧
      evaluate withdrawn [someAmountIsOne] = .undetermined := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> decide

/-- An undetermined decision promises nothing: more evidence can take it either way. -/
theorem undetermined_can_become_either :
    evaluate withdrawn [someAmountIsOne] = .undetermined ∧
      evaluate ⟨noInputs, noInputs, fun _ => [⟨[("amount", .num 1)]⟩], fun _ => false⟩
        [someAmountIsOne] = .supported ∧
      evaluate withdrawn [everyAmountIsOne] = .undetermined ∧
      evaluate ⟨noInputs, noInputs, fun _ => [⟨[("amount", .num 2)]⟩], fun _ => false⟩
        [everyAmountIsOne] = .contradicted := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> decide

end Verified.Contract

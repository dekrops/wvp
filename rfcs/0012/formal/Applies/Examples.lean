import Applies.Theorems

/-!
Examples on Language 2 (RFC 0008), decided by `decide`. The tax check applies to an invoice that
is not under reverse charge (§13b UStG); under reverse charge the buyer owes the tax, so the
invoice shows none, and the check does not apply. Without `appliesWhen`, such an invoice comes
out `CONTRADICTED`, as S022 found for 46,080 of F007's invoices.
-/

namespace Applies.Examples

open Verified.Contract

def invoice (reverseCharge : Bool) (net tax gross : Int) : Record :=
  ⟨[("gross", .num gross), ("id", .text "INV-1"), ("net", .num net), ("reverseCharge", .bool reverseCharge),
    ("tax", .num tax)]⟩

def env (records : List Record) (closed : Bool) : Env where
  inputs := fun n => if n = "invoice" then some (.text "INV-1") else none
  params := fun _ => none
  records := fun k => if k = "invoice" then records else []
  closed := fun k => k = "invoice" && closed

def theInvoice (body : WCL2.Pred) : WCL2.Pred :=
  .ex "i" "invoice" (.and (.cmp .eq (.field "i" "id") (.input "invoice")) body)

/-- The invoice is not under reverse charge. -/
def notReverseCharge : WCL2.Pred :=
  theInvoice (.cmp .eq (.field "i" "reverseCharge") (.lit .bool (.bool false)))

/-- 19 % tax, to the cent: 100 × tax = 19 × net. -/
def taxAt19 : WCL2.Pred :=
  theInvoice (.cmp .eq (.scale 100 (.field "i" "tax")) (.scale 19 (.field "i" "net")))

/-- The gross is net plus tax. -/
def grossAddsUp : WCL2.Pred :=
  theInvoice (.cmp .eq (.add (.field "i" "net") (.field "i" "tax")) (.field "i" "gross"))

def withCondition : List (Requirement WCL2.Pred) :=
  [⟨none, grossAddsUp⟩, ⟨some notReverseCharge, taxAt19⟩]

def withoutCondition : List (Requirement WCL2.Pred) :=
  [⟨none, grossAddsUp⟩, ⟨none, taxAt19⟩]

def onlyTax : List (Requirement WCL2.Pred) := [⟨some notReverseCharge, taxAt19⟩]

def decideIn (e : Env) (requirements : List (Requirement WCL2.Pred)) : Outcome :=
  evaluate (fun p => p.eval e []) requirements

def resultsIn (e : Env) (requirements : List (Requirement WCL2.Pred)) : List Result :=
  requirements.map (result fun p => p.eval e [])

/-- A domestic invoice, 1000.00 + 190.00 = 1190.00. -/
theorem domestic : decideIn (env [invoice false 100000 19000 119000] true) withCondition = .supported := by decide

/-- A domestic invoice with 7 % tax where 19 % is due: the check applies, and fails. -/
theorem domestic_wrong_tax :
    decideIn (env [invoice false 100000 7000 107000] true) withCondition = .contradicted := by decide

/-- Under reverse charge no tax is shown: the tax check does not apply, and the invoice is
    supported by the requirement that does. -/
theorem reverse_charge :
    resultsIn (env [invoice true 100000 0 100000] true) withCondition = [.true, .notApplicable] ∧
      decideIn (env [invoice true 100000 0 100000] true) withCondition = .supported := by decide

/-- Without the condition, the same invoice is `CONTRADICTED`, like a real failure. -/
theorem reverse_charge_without_condition :
    decideIn (env [invoice true 100000 0 100000] true) withoutCondition = .contradicted := by decide

/-- A contract whose only requirement does not apply is `NOT_APPLICABLE`. -/
theorem nothing_applies :
    decideIn (env [invoice true 100000 0 100000] true) onlyTax = .notApplicable := by decide

/-- The invoice not yet seen, in a listing not declared complete: it may yet apply. -/
theorem condition_unknown :
    resultsIn (env [] false) onlyTax = [.unknown] ∧ decideIn (env [] false) onlyTax = .undetermined := by decide

end Applies.Examples

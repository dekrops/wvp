import WCL2.Theorems

/-!
Two Procure-to-Pay requirements that Work Contract Language 1 cannot state, decided by the model.
Amounts are in cents (`money "EUR" 2`); the records are illustrative, not observations.

* `R_MATCHES_ORDER`: the invoice is within 1 % of its purchase order:
  `100 × |invoice.amount − order.amount| ≤ order.amount`.
* `R_NOT_OVERPAID`: what was allocated to the invoice is at most its amount:
  `sum(paymentMatch.amount where paymentMatch.invoice = invoice.id) ≤ invoice.amount`.
-/

namespace WCL2.Examples

open Verified.Contract
open WCL2

def eur : Ty := .money "EUR" 2
def text (s : String) : Value := .text s
def cents (n : Int) : Value := .num n

def field (var name : String) : Term := .field var name
def eq (left right : Term) : Pred := .cmp .eq left right

/-- The invoice under evaluation, bound to `i`. -/
def theInvoice (body : Pred) : Pred :=
  .ex "i" "invoice" (.and (eq (field "i" "id") (.input "invoice")) body)

def matchesOrder : Pred :=
  theInvoice <|
    .ex "o" "purchaseOrder" <|
      .and (eq (field "o" "id") (field "i" "order"))
        (.cmp .le (.scale 100 (.abs (.sub (field "i" "amount") (field "o" "amount"))))
          (field "o" "amount"))

def notOverpaid : Pred :=
  theInvoice <|
    .agg (.sum "amount") "m" "paymentMatch" (eq (field "m" "invoice") (field "i" "id")) .le
      (field "i" "amount")

def requirements : List Pred := [matchesOrder, notOverpaid]

def invoice : Record := ⟨[("id", text "INV-1"), ("order", text "PO-7"), ("amount", cents 10050)]⟩
def order : Record := ⟨[("id", text "PO-7"), ("amount", cents 10000)]⟩
def payment (amount : Int) : Record := ⟨[("invoice", text "INV-1"), ("amount", cents amount)]⟩
/-- A payment to another invoice: not counted. -/
def otherPayment : Record := ⟨[("invoice", text "INV-2"), ("amount", cents 99999)]⟩

def environment (payments : List Record) (paymentsComplete : Bool) : Env where
  inputs := fun name => if name = "invoice" then some (text "INV-1") else none
  params := fun _ => none
  records := fun kind =>
    if kind = "invoice" then [invoice]
    else if kind = "purchaseOrder" then [order]
    else if kind = "paymentMatch" then payments
    else []
  closed := fun kind => if kind = "paymentMatch" then paymentsComplete else true

/-- 0.5 % above the order, paid exactly in two parts: supported. -/
theorem within_tolerance_and_paid_once :
    evaluate (environment [payment 6000, payment 4050, otherPayment] true) requirements =
      .supported := by decide

/-- One more cent allocated than the invoice is for: contradicted. -/
theorem overpaid_is_contradicted :
    evaluate (environment [payment 6000, payment 4051] true) requirements = .contradicted := by
  decide

/-- The same payments, but no source declared the listing of matches complete: the sum is not a
    sum, so the requirement is unknown and the decision undetermined, never supported. -/
theorem open_listing_is_undetermined :
    evaluate (environment [payment 6000, payment 4050] false) requirements = .undetermined := by
  decide

/-! Four eyes, counted: at least two approvals of the payment run, none by its creator.
Records are distinct by key (one approval per approver), so counting approvals counts people. -/

def fourEyes : Pred :=
  .ex "r" "paymentRun" <|
    .and (eq (field "r" "id") (.input "run")) <|
      .agg .count "a" "approval"
        (.and (eq (field "a" "run") (field "r" "id"))
          (.cmp .ne (field "a" "approver") (field "r" "createdBy")))
        .ge (.lit .int (.num 2))

def run : Record := ⟨[("id", text "RUN-3"), ("createdBy", text "kim")]⟩
def approval (who : String) : Record := ⟨[("run", text "RUN-3"), ("approver", text who)]⟩

def runEnvironment (approvals : List Record) : Env where
  inputs := fun name => if name = "run" then some (text "RUN-3") else none
  params := fun _ => none
  records := fun kind => if kind = "paymentRun" then [run] else if kind = "approval" then approvals else []
  closed := fun _ => true

theorem two_other_approvers_suffice :
    evaluate (runEnvironment [approval "lea", approval "max"]) [fourEyes] = .supported := by decide

/-- The creator's own approval is not counted: one other approver is not enough. -/
theorem creator_approval_not_counted :
    evaluate (runEnvironment [approval "kim", approval "lea"]) [fourEyes] = .contradicted := by
  decide

/-- The model counts what it is given: the same approval listed twice is counted twice, and one
    person passes four eyes. Such an environment is not `Distinct`, and none is evaluated:
    Language 1's step 5 makes facts with equal keys one record. With the approver part of the
    approval's key, a second approval by the same person is the same record. -/
theorem duplicate_approval_counts_twice :
    evaluate (runEnvironment [approval "lea", approval "lea"]) [fourEyes] = .supported := by decide

theorem duplicate_listing_is_not_distinct :
    ¬ Distinct (runEnvironment [approval "lea", approval "lea"]) := by
  intro distinct
  have := distinct "approval"
  simp [runEnvironment] at this

end WCL2.Examples

import WCL2G.Theorems

/-!
The case that motivates the RFC, decided by the model. The pilot adapter couldn't read one
payment row of invoice INV-02 (`pilot-adapter`, the messy sample). So the payments are not
complete as a whole, but they are complete for INV-01: the adapter read every payment row whose
invoice is INV-01.

The control is "paid within approval": the sum of the invoice's payments is at most what was
approved, 100.00 here. Amounts are in cents; the records are illustrative.
-/

namespace WCL2G.Examples

open Verified.Contract
open WCL2 (Aggregate)
open WCL2G

def eur : Ty := .money "EUR" 2
def text (s : String) : Value := .text s
def num (n : Int) : Value := .num n
def eq (left right : Term) : Pred := .cmp .eq left right
def payment (invoice : String) (amount : Int) : Record :=
  ⟨[("invoice", text invoice), ("amount", num amount)]⟩
def approval (invoice : String) : Record := ⟨[("invoice", text invoice), ("approver", text "ana")]⟩

/-- The payments of the invoice asked about, summed: with `per`, over its group; without, over
    the whole kind, filtered by the body, as RFC 0011 writes it. -/
def paid (perInvoice : Bool) : Term :=
  .agg (.sum "amount") "p" "payment" (if perInvoice then some "invoice" else none) (.input "invoice")
    (eq (.field "p" "invoice") (.input "invoice"))

def paidWithinApproval (perInvoice : Bool) : Pred := .cmp .le (paid perInvoice) (.lit eur (num 10000))

/-- Some approval of the invoice asked about. -/
def approved (perInvoice : Bool) : Pred :=
  .ex "a" "approval" (if perInvoice then some "invoice" else none) (.input "invoice")
    (eq (.field "a" "invoice") (.input "invoice"))

/-- A statement's groups: the values it lists, or every value but those it lists. -/
inductive Covers where
  | only (values : List Value)
  | except (values : List Value)

def Covers.has : Covers → Value → Bool
  | .only values, value => decide (value ∈ values)
  | .except values, value => !decide (value ∈ values)

/-- One month: neither kind is complete as a whole; the groups in `declared` are, each given
    as (kind, field, the values covered). -/
def month (asked : Option String) (payments approvals : List Record)
    (declared : List (String × String × Covers)) : GEnv where
  base := {
    inputs := fun name => if name = "invoice" then asked.map text else none
    params := fun _ => none
    records := fun kind => if kind = "payment" then payments else if kind = "approval" then approvals else []
    closed := fun _ => false }
  groups := fun kind field value =>
    declared.any fun statement => statement.1 == kind && statement.2.1 == field && statement.2.2.has value

def payments : List Record := [payment "INV-01" 6000, payment "INV-01" 4000, payment "INV-02" 2500]
def complete01 : List (String × String × Covers) :=
  [("payment", "invoice", .only [text "INV-01"]), ("approval", "invoice", .only [text "INV-01"])]

/-- What an adapter can say after rejecting one payment row of INV-02: the payments are complete
    for every invoice except INV-02. -/
def allButInv02 : List (String × String × Covers) := [("payment", "invoice", .except [text "INV-02"])]

/-- **With `per`, INV-01 is decided**: its payments are complete, they add up to 100.00, within
    the approval. -/
theorem paid_within_approval_decided :
    (paidWithinApproval true).eval (month (some "INV-01") payments [] complete01) [] = .true := by decide

/-- **Without `per`, it isn't**: the payments as a whole are open, so their sum has no value
    (RFC 0008), although nothing is missing for INV-01. This is today's result. -/
theorem paid_within_approval_today :
    (paidWithinApproval false).eval (month (some "INV-01") payments [] complete01) [] = .unknown := by decide

/-- **INV-02 stays undecided**: a payment of it couldn't be read, so its group isn't declared
    complete. Missing evidence never becomes a pass. -/
theorem other_invoice_undecided :
    (paidWithinApproval true).eval (month (some "INV-02") payments [] complete01) [] = .unknown := by decide

/-- **An overpayment is still caught**: 130.00 paid in a complete group. -/
theorem overpaid_caught :
    (paidWithinApproval true).eval
      (month (some "INV-01") (payment "INV-01" 3000 :: payments) [] complete01) [] = .false := by decide

/-- **A missing approval is found**: no approval of INV-01 in its complete group, though the
    approvals as a whole are open. -/
theorem missing_approval_found :
    (approved true).eval (month (some "INV-01") payments [approval "INV-02"] complete01) [] = .false := by
  decide

/-- Without `per`, the same is unknown: today, an open listing can't show something is missing. -/
theorem missing_approval_today :
    (approved false).eval (month (some "INV-01") payments [approval "INV-02"] complete01) [] = .unknown := by
  decide

/-- **A group names a value, not a pattern**: payments complete for INV-01 says nothing about
    INV-010. -/
theorem group_is_exact :
    (paidWithinApproval true).eval (month (some "INV-010") payments [] complete01) [] = .unknown := by decide

/-- **No key, no group**: with no invoice asked about, the group is unknown. -/
theorem no_key_is_unknown :
    (paidWithinApproval true).eval (month none payments [] complete01) [] = .unknown := by decide

/-- A group declared complete for another kind doesn't close this one. -/
theorem group_is_per_kind :
    (approved true).eval
      (month (some "INV-01") payments [] [("payment", "invoice", .only [text "INV-01"])]) [] = .unknown := by decide

/-- **"Every invoice except INV-02"** decides INV-01, and an invoice with no payments at all:
    nothing was paid, within any approval. -/
theorem except_decides_others :
    (paidWithinApproval true).eval (month (some "INV-01") payments [] allButInv02) [] = .true ∧
      (paidWithinApproval true).eval (month (some "INV-03") payments [] allButInv02) [] = .true := by
  decide

/-- … and leaves INV-02 undecided. -/
theorem except_leaves_its_exception :
    (paidWithinApproval true).eval (month (some "INV-02") payments [] allButInv02) [] = .unknown := by decide

end WCL2G.Examples

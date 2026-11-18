import WCL2T.Theorems

/-!
Three Procure-to-Pay controls that RFC 0008 cannot state, decided by the model. Amounts are in
cents (`money "EUR" 2`), rates in basis points; the records are illustrative, not observations.

* `R_AMOUNTS_ADD_UP`: the invoice's net and tax, over its rate groups, add up to its gross:
  `sum(g.net) + sum(g.tax) = i.gross`. Two aggregates added (§14(4) Nr. 7–8 UStG, and F007's
  `classify`; shadowplay S022 had to work around it by duplicating every amount).
* `R_INVOICED_WITHIN_RECEIVED`: the cumulative three-way match. Over all invoice lines against
  the order, the quantity invoiced is at most the quantity received:
  `sum(l.qty where l.order = o.id) ≤ sum(r.qty where r.order = o.id)`. An aggregate compared with
  an aggregate (F002's `spec_never_overbilled`, as a requirement).
* `R_TAX_ROUNDED`: each rate group's tax is its net times its rate, rounded half up, within one
  cent: `10000·(tax − 1) ≤ rateBps · net + 5000 < 10000·(tax + 2)`. The rate is read from the
  group (`mul`), not listed in the contract, so 10 % is decided like 19 % (S022 had to list rates).
-/

namespace WCL2T.Examples

open Verified.Contract
open WCL2 (Aggregate)
open WCL2T

def eur : Ty := .money "EUR" 2
def text (s : String) : Value := .text s
def num (n : Int) : Value := .num n

def field (var name : String) : Term := .field var name
def eq (left right : Term) : Pred := .cmp .eq left right
def lit (n : Int) : Term := .lit eur (num n)

/-- The invoice under evaluation, bound to `i`. -/
def theInvoice (body : Pred) : Pred :=
  .ex "i" "invoice" (.and (eq (field "i" "id") (.input "invoice")) body)

def groupsOf (fieldName : String) : Term :=
  .agg (.sum fieldName) "g" "rateGroup" (eq (field "g" "invoice") (field "i" "id"))

def amountsAddUp : Pred :=
  theInvoice (eq (.add (groupsOf "net") (groupsOf "tax")) (field "i" "gross"))

def invoicedWithinReceived : Pred :=
  .ex "o" "purchaseOrder" <|
    .and (eq (field "o" "id") (.input "order")) <|
      .cmp .le
        (.agg (.sum "qty") "l" "invoiceLine" (eq (field "l" "order") (field "o" "id")))
        (.agg (.sum "qty") "r" "receipt" (eq (field "r" "order") (field "o" "id")))

def taxRounded : Pred :=
  theInvoice <|
    .all "g" "rateGroup" <|
      .or (.not (eq (field "g" "invoice") (field "i" "id"))) <|
        let rounded := Term.add (.mul (field "g" "rateBps") (field "g" "net")) (lit 5000)
        .and (.cmp .le (.scale 10000 (.sub (field "g" "tax") (lit 1))) rounded)
          (.cmp .lt rounded (.scale 10000 (.add (field "g" "tax") (lit 2))))

/-! ### Σ(net + tax) = gross -/

def invoice (gross : Int) : Record := ⟨[("id", text "INV-1"), ("gross", num gross)]⟩
def group (net tax bps : Int) : Record :=
  ⟨[("invoice", text "INV-1"), ("net", num net), ("tax", num tax), ("rateBps", num bps)]⟩
/-- A group of another invoice: not counted. -/
def otherGroup : Record := ⟨[("invoice", text "INV-2"), ("net", num 999), ("tax", num 99), ("rateBps", num 1900)]⟩

def invoiceEnv (gross : Int) (groups : List Record) (groupsComplete : Bool) : Env where
  inputs := fun name => if name = "invoice" then some (text "INV-1") else none
  params := fun _ => none
  records := fun kind => if kind = "invoice" then [invoice gross]
    else if kind = "rateGroup" then groups else []
  closed := fun kind => if kind = "rateGroup" then groupsComplete else true

/-- 19 % on EUR 168.00 and 7 % on EUR 100.00: 168.00 + 31.92 + 100.00 + 7.00 = 306.92. -/
theorem amounts_add_up :
    evaluate (invoiceEnv 30692 [group 16800 3192 1900, group 10000 700 700, otherGroup] true)
      [amountsAddUp] = .supported := by decide

/-- One cent more on the gross: contradicted. -/
theorem amounts_off_by_a_cent :
    evaluate (invoiceEnv 30693 [group 16800 3192 1900, group 10000 700 700] true)
      [amountsAddUp] = .contradicted := by decide

/-- Rate groups not declared complete: the sums are not sums, so undetermined, never supported. -/
theorem amounts_open_groups :
    evaluate (invoiceEnv 30692 [group 16800 3192 1900, group 10000 700 700] false)
      [amountsAddUp] = .undetermined := by decide

/-! ### The rate read from the group -/

/-- 19 % and 7 %, each rounded half up: supported. -/
theorem tax_rounded :
    evaluate (invoiceEnv 30692 [group 16800 3192 1900, group 10000 700 700] true)
      [taxRounded] = .supported := by decide

/-- 10 % is decided like any other rate, with no list of rates in the contract. -/
theorem tax_at_ten_percent :
    evaluate (invoiceEnv 11000 [group 10000 1000 1000] true) [taxRounded] = .supported := by decide

/-- Tax two cents too high: beyond the one-cent tolerance, contradicted. -/
theorem tax_two_cents_high :
    evaluate (invoiceEnv 30694 [group 16800 3194 1900, group 10000 700 700] true)
      [taxRounded] = .contradicted := by decide

/-- Half a cent rounds up: 19 % of EUR 168.03 is 31.9257, so 31.93; 31.92 is within the
    tolerance, 31.91 is not. -/
theorem tax_rounds_half_up :
    evaluate (invoiceEnv 0 [group 16803 3193 1900] true) [taxRounded] = .supported ∧
    evaluate (invoiceEnv 0 [group 16803 3191 1900] true) [taxRounded] = .contradicted := by
  decide

/-! ### The cumulative three-way match -/

def order : Record := ⟨[("id", text "PO-7")]⟩
def line (qty : Int) : Record := ⟨[("order", text "PO-7"), ("qty", num qty)]⟩
def receipt (qty : Int) : Record := ⟨[("order", text "PO-7"), ("qty", num qty)]⟩

def orderEnv (lines receipts : List Record) (receiptsComplete : Bool) : Env where
  inputs := fun name => if name = "order" then some (text "PO-7") else none
  params := fun _ => none
  records := fun kind => if kind = "purchaseOrder" then [order]
    else if kind = "invoiceLine" then lines else if kind = "receipt" then receipts else []
  closed := fun kind => if kind = "receipt" then receiptsComplete else true

/-- Two invoices of 6 and 4 against receipts of 7 and 3: within, supported. -/
theorem invoiced_within_received :
    evaluate (orderEnv [line 6, line 4] [receipt 7, receipt 3] true) [invoicedWithinReceived]
      = .supported := by decide

/-- A third invoice of 1: eleven invoiced against ten received, contradicted. -/
theorem invoiced_beyond_received :
    evaluate (orderEnv [line 6, line 4, line 1] [receipt 7, receipt 3] true)
      [invoicedWithinReceived] = .contradicted := by decide

/-- Receipts not declared complete: what was received isn't known, so undetermined. -/
theorem receipts_open :
    evaluate (orderEnv [line 6, line 4] [receipt 7, receipt 3] false) [invoicedWithinReceived]
      = .undetermined := by decide

end WCL2T.Examples

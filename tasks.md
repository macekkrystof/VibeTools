# Human Notes / Backlog (optional)

- Open questions:
  - Expenses grid reference in Logeto.Server.Web was not found; use Contracts area + CostsAndRevenues as DevExtreme patterns.

- Nice-to-haves:
  - If needed, add a helper to mirror WebSite DateRange filter UI in DevExtreme (toolbar extension).

- Risks:
  - WebSite Contracts grid relies on WebForms-specific behavior (Rights popup, EndContract control, SqlDataSource params) that may require new services/endpoints.
  - Some fields/permissions are driven by Settings.Instance.User and SystemBehavior; ensure equivalents exist in ASP.NET Core layer.

- Analysis summary (WebSite Contracts):
  - Source files: [Contracts.aspx](Logeto.Server.WebSite/WebSite/Contracts/Contracts.aspx), [Contracts.aspx.cs](Logeto.Server.WebSite/WebSite/Contracts/Contracts.aspx.cs), [Contracts.js](Logeto.Server.WebSite/WebSite/Contracts/Contracts.js)
  - Toolbar/actions: Rights popup, EndContract (admin), Subcontracts (if enabled), CostsAndRevenues (admin or CanDisplayCostsAndRevenues), export PDF/XLS, report UnitGeneralSummary.
  - Filters: DateRange (default ThisYear) + Validity filter; params DATE_START/DATE_END/ACTIVE/MASK_INACCESSIBLE.
  - Columns (visible by default): POPIS (Title, sort asc), KOD, KONTAKT_POPIS, SUMMARY_REVENUE, SUMMARY_COST, SUMMARY_BALANCE, HOURS_WORKED. Additional columns hidden by default: dates (DATUM_ZAHAJENI/UKONCENI, TIMESTAMP_CREATED/CHANGED), persons, source names, responsible person, description, note, billable text, invoiced cost totals, % spent, remaining and planned costs/hours.
  - Unbound column: _BILLABLE text from BILLABLE flags.
  - Summaries: TotalSummary + GroupSummary for cost/hours fields.
  - Edit form tabs: Basic (Name/Code/Contact/Responsible/Description/Start/End), Note, Budget (cost/time planned + computed spent/remains). Billable flags with “forbid editing”.
  - Budget calculations: uses P_GLO_CONTRACTS_WORKED_TOTAL for totals; JS updates spent/remains and red coloring when negative.
  - Permissions/tenant: omnetic -> read-only edit form; hide columns based on rights; hide budget columns for new billing or missing rights.

- Analysis summary (Web Contracts in ASP.NET Core):
  - Existing scaffold: [ContractsController.cs](Logeto.Server.Web/Logeto.Server.Web/Areas/Contracts/Controllers/ContractsController.cs), [Contracts.cshtml](Logeto.Server.Web/Logeto.Server.Web/Areas/Contracts/Views/Contracts.cshtml), [Contracts.ts](Logeto.Server.Web/Logeto.Server.Web/Areas/Contracts/Scripts/Contracts.ts), [ContractsGridDataView.cs](Logeto.Server.Web/Logeto.Server.Web/DataViews/ContractsGridDataView.cs).
  - Current grid only shows Name/Code/Description and has empty toolbar handlers.

---

# Detailed Audit — WebSite Contracts Grid

## Columns (order & visibility)

| # | FieldName | Caption (I18n key) | Type | VisibleIndex | Visible | Width | Format | Notes |
|---|-----------|---------------------|------|-------------|---------|-------|--------|-------|
| 1 | GUID | — | Text | — | false | — | — | Hidden, not in customization form |
| 2 | POPIS | ContractsGridColumnTitle | Text (Unbound) | 4 | true | 350px | — | Default sort: Ascending |
| 3 | KOD | ContractsGridColumnCode | Text (Unbound) | 5 | true | 120px | — | |
| 4 | KONTAKT_POPIS | ContractsGridColumnContact | Text (Unbound) | 6 | true | 150px | — | |
| 5 | DATUM_ZAHAJENI | ContractsGridColumnStartDate | Date | — | false | 130px | Date | ConvertEmptyStringToNull |
| 6 | DATUM_UKONCENI | ContractsGridColumnEndDate | Date | — | false | 130px | Date | ConvertEmptyStringToNull |
| 7 | TIMESTAMP_CREATED | ContractsGridColumnCreationDate | DateTime (Unbound) | — | false | 150px | DateTime (Seconds) | |
| 8 | TIMESTAMP_CHANGED | ContractsGridColumnDateOfChange | DateTime (Unbound) | — | false | 150px | DateTime (Seconds) | |
| 9 | PERSON_CREATED | ContractsGridColumnCreated | Text (Unbound) | — | false | 150px | — | Person format |
| 10 | PERSON_CHANGED | ContractsGridColumnChanged | Text (Unbound) | — | false | 150px | — | Person format |
| 11 | SOURCE_NAME_CREATED | ContractsGridColumnSourceNameCreated | Text (Unbound) | — | false | 150px | — | |
| 12 | SOURCE_NAME | ContractsGridColumnSourceNameChanged | Text (Unbound) | — | false | 150px | — | |
| 13 | RESPONSIBLE_PERSON_NAME | ContractsGridColumnResponsiblePerson | Text | — | false | 150px | — | |
| 14 | DESCRIPTION | ContractsGridColumnDescription | Text | — | false | 200px | — | |
| 15 | NOTE | SubcontractsGridColumnNote | Text | — | false | 200px | — | |
| 16 | _BILLABLE | OtherExpensesGridColumnBillable | Text (Unbound) | — | false | 130px | — | Computed from BILLABLE flags |
| 17 | COST_INVOICED | ContractsGridColumnCostInvoiced | Text | — | false | 100px | N0 | Right-aligned |
| 18 | COST_DISCARTED | ContractsGridColumnCostDiscarted | Text | — | false | 100px | N0 | Right-aligned |
| 19 | COST_NOT_INVOICED | ContractsGridColumnCostNotInvoiced | Text | — | false | 100px | N0 | Right-aligned |
| 20 | SUMMARY_COST | ContractsGridColumnSummaryCost | Text | 7 | true | 100px | N0 | Right-aligned |
| 21 | SUMMARY_REVENUE | ContractsGridColumnSummaryRevenue | Text | 6 | true | 100px | N0 | Right-aligned |
| 22 | SUMMARY_BALANCE | ContractsGridColumnSummaryProfit | Text | 8 | true | 100px | N0 | Right-aligned |
| 23 | HOURS_WORKED | ContractsGridColumnHoursWorked | Text | 9 | true | 110px | Hours | Right-aligned |
| 24 | COSTS_SPENT | ContractsGridColumnCostsSpent | Text | — | false | 110px | P0 | Right-aligned, % |
| 25 | HOURS_SPENT | ContractsGridColumnTimeSpent | Text | — | false | 100px | P0 | Right-aligned, % |
| 26 | COSTS_REMAINS | ContractsGridColumnRemainingCosts | Text | — | false | 110px | N0 | Right-aligned |
| 27 | HOURS_REMAINS | ContractsGridColumnRemainingTime | Text | — | false | 100px | Hours | Right-aligned |
| 28 | COSTS_PLANNED | ContractsGridColumnBudgetCosts | Text | — | false | 110px | N0 | Right-aligned |
| 29 | HOURS_PLANNED | ContractsGridColumnBudgetTime | Text | — | false | 100px | Hours | Right-aligned |

## Default Sort
- POPIS ascending (SortIndex=0)

## Export
- PDF and XLS enabled (ShowExportPDF/ShowExportXLS)
- ExportColumnsAsTimeFieldNames: HOURS_WORKED, HOURS_REMAINS, HOURS_PLANNED

## Reports
- UnitGeneralSummary (ContractsSummaryContractEval)

## Total & Group Summaries (Custom SummaryType)
- TotalSummary fields: COST_INVOICED, COST_DISCARTED, COST_NOT_INVOICED, SUMMARY_COST, SUMMARY_REVENUE, SUMMARY_BALANCE, HOURS_WORKED, COSTS_REMAINS, HOURS_REMAINS, COSTS_PLANNED, HOURS_PLANNED
- GroupSummary: same fields, shown in group footer

## Filters
- **DateRange**: default ThisYear, session-persisted (FilterContractsPeriod), auto-postback
- **Validity filter**: ShowValidityFilter=true (maps to ACTIVE param)
- Select params: ID_ACCOUNT (session), DATE_START, DATE_END, ACTIVE, MASK_INACCESSIBLE, EVALUATE_SUMMARIES (default true), INCLUDE_FUTURE_RECORDS (default true)

## Stored Procedures
- Select: P_GLO_UTVARY_R
- Insert: P_GLO_UTVARY_I
- Update: P_GLO_UTVARY_U
- Delete: P_GLO_UTVARY_D
- Budget totals: P_GLO_CONTRACTS_WORKED_TOTAL (params: @ID_ACCOUNT, @ID_CONTRACT; returns COSTS_WORKED, HOURS_WORKED)

## Toolbar Actions
1. **EndContract** — admin only (IsContractsAndInvoicingAdmin), multi-select, disabled when no row selected
2. **Subcontracts** — shown if SubcontractsGloballyEnabled, disabled until row focused; redirects to Subcontracts with State param
3. **CostsAndRevenues** — admin or CanDisplayCostsAndRevenues, disabled until row focused; redirects with Contract GUID param
4. **Rights** — shown if not read-only (admin); opens Rights popup for EntityType.Contract
5. **Print/Export** — PDF/XLS built-in grid export

## Edit Form (Popup, 500px)
### Tab 1: Basic Info (tabBasicInfo)
- POPIS (Name) — required, max 250
- KOD (Code) — max 15
- Contact combo (ID_KONTAKTU) — dropdown with add/delete buttons, callback
- Responsible Person combo (GUID_RESPONSIBLE_PERSON) — dropdown with delete button
- DESCRIPTION — max 500
- DATUM_ZAHAJENI (Start Date) — date picker, nullable
- DATUM_UKONCENI (End Date) — date picker, nullable
- Billable fieldset: default value combo (Billable/None) + "Forbid editing" checkbox (stored as bit-flags in BILLABLE field)

### Tab 2: Note
- NOTE — memo, 20 rows

### Tab 3: Budget (hidden if IsNewBilling)
- Cost Budget: PlannedCosts (N0, validated as positive int, max decimal(18,3)), ActualCosts (label from P_GLO_CONTRACTS_WORKED_TOTAL), CostsSpent (%), RemainingCosts (abs value, red if negative)
- Time Budget: PlannedTime (N0, validated as positive int, max decimal(8,0)), TimeWorked (label), TimeSpent (%), RemainingTime (abs value, red if negative)
- JS: PlannedCostsChanged/PlannedTimeChanged recompute spent/remains/color dynamically

## Permissions & Tenant Rules
- **omnetic tenant**: ReadOnly=true, hide add/delete, edit form controls set to read-only, edit buttons hidden
- **Non-admin (ReadOnly=true)**: hide columns NOTE, _BILLABLE, TIMESTAMP_CREATED/CHANGED, PERSON_CREATED/CHANGED, SOURCE_NAME_CREATED/SOURCE_NAME
- **!CanDisplayContractsCosts**: hide COST_INVOICED, COST_DISCARTED, COST_NOT_INVOICED, SUMMARY_COST
- **!CanDisplayContractsRevenues**: hide SUMMARY_REVENUE
- **!CanDisplayContractsCosts || !CanDisplayContractsRevenues**: hide SUMMARY_BALANCE
- **!CanDisplayContractsTimeWorked**: hide HOURS_WORKED
- **!CanDisplayContractsTimeBudget || IsNewBilling**: hide HOURS_SPENT, HOURS_REMAINS, HOURS_PLANNED
- **!CanDisplayContractsCostsBudget || IsNewBilling**: hide COSTS_SPENT, COSTS_REMAINS, COSTS_PLANNED
- **Reports hidden**: if ReadOnly AND (!CanDisplayContractsCosts || !CanDisplayContractsRevenues || !CanDisplayContractsTimeWorked)

## Unbound Column Logic
- _BILLABLE: reads BILLABLE (short), converts to BillableFlags enum, displays text via SharedBehavior.GetBillableFlagsText()

## JS Behaviors (Contracts.js)
- FocusedRowChanged: enables/disables Subcontract and CostsAndRevenues toolbar items based on focused row
- InitContractsEditForm: if omnetic tenant, hides edit buttons and sets all form controls read-only
- PlannedCostsChanged/PlannedTimeChanged: recalculate budget spent/remains/color
- UpdateColor: red if negative, black otherwise
- InitRightsPopupHelpGridHandler: shows rights popup help on first insert

## Layout Settings
- LayoutSettingsKey: c97860cc-e225-4d92-911c-4ee3fd3144db

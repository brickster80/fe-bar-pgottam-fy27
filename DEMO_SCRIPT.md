# Demo Script — "Authorized access, unauthorized movement"

**Industry:** Financial services (Halcyon Financial, fictional) · **Runtime:** ~20 min + Q&A
**Workspace:** e2-demo-field-eng · **Catalog/schema:** `capmarkets_stg.febar_e2e`
**One-liner:** *Unity Catalog tells you who read the vendor banking table. It can't tell you, on its own, that the read came from a loaner laptop, that the 480,000 rows landed in a CSV, or that the CSV went to a personal Dropbox. Fusing Databricks audit, query history and lineage with identity, endpoint and DLP signals turns four separate weak alerts into one explainable investigation, without assuming the employee is guilty.*

## Links

| What | Where |
|---|---|
| App — Access & Movement Investigations | https://febar-e2e-console-1444828305810485.aws.databricksapps.com |
| AI/BI dashboard (also embedded in the app's **Dashboard** tab) | https://e2-demo-field-eng.cloud.databricks.com/dashboardsv3/01f1cbe1f41c13c3b4c1964e652762d9/published |
| Genie space | "Authorized Access, Unauthorized Movement" — `01f1cbe0c38c1d129f67a95d56d9ac69` |
| Lakeflow pipeline | `febar-e2e-access-movement` |
| Job | `febar-e2e-access-movement-daily` (ingest → ML → GenAI assessment → Lakebase refresh; schedule paused) |
| Lakebase | Project `febar-e2e` → UC catalog `febar_e2e_lakebase` (`e2e` synced, `e2e_response` app-owned) |
| UC model | `capmarkets_stg.febar_e2e.access_movement_iforest@prod` |

## Governed assets

| Logical asset (in the logs) | Physical stand-in (real UC table) | Sensitivity | Expected use | UC control |
|---|---|---|---|---|
| `finance_prod.reporting.monthly_summary` | `reporting_monthly_summary` | confidential | Routine analyst reporting | tags |
| `finance_prod.treasury.vendor_bank_accounts` | `treasury_vendor_bank_accounts` | restricted | Approved treasury workflows | tags + **column masks** on routing/account numbers |
| `finance_prod.strategy.acquisition_forecast` | `strategy_acquisition_forecast` | highly restricted (MNPI) | Corporate development only | tags + **row filter** |

## The incident (America/New_York, 2026-09-24): what the build produces

| Local | Source | Observation (from `gold_incident_timeline`) | Why it matters |
|---|---|---|---|
| 21:40 | Okta | Alex Morgan signs in from **LOANER-NYC-07** (never associated with Alex), IdP risk MEDIUM | Identity risk, not proof of compromise |
| 21:43 | Databricks audit + lineage | First-ever query of `vendor_bank_accounts` (25 rows) | Sensitive-data access anomaly |
| 21:46 | Databricks query history | **480,000 rows** via DBeaver vs ~7,016 on a normal day (**68× self, 1,034× peers**) | Unusual collection volume, not proof of export |
| 21:49 | CrowdStrike EDR | `dbeaver.exe` creates `vendor_master_full.csv` (86.4 MB) | Local materialization by the query client |
| 21:53 | Netskope DLP | Same SHA-256 uploaded to a **personal Dropbox** account; profile "Bank account numbers" | Data crossed an unauthorized boundary |
| 21:55 | Correlation | `INC-20260924-E-0042`, risk 100, T1078 · T1213 · T1074.001 · T1567.002 | One explainable investigation |

**Decoys (they show the fusion is doing real work):**
- **Priya Shah** (Accounting) pulls 52,000 vendor rows and uploads them, but to the corporate SharePoint under exception **EXC-4471** → *Explained by exception*, P4.
- **Kevin Brooks** (Engineering) uploads 410 MB to a personal Dropbox, but there's no lineage to any governed asset → *DLP only*, low.
- **Daniel Okafor** (Treasury) signs in from a new managed laptop (refresh) with normal activity → no incident.
- 793 sensitive files go to the approved corporate tenant every quarter → not incidents.

**Funnel:** 21,012 sensitive queries → 134 employees on restricted assets → 116 ML-anomalous employee-days → 1,590 files materialized → **1 unauthorized movement** → **1 P1 incident**.

---

## Scene 1 — The problem (2 min)
> "Alex Morgan is a finance analyst with a *legitimate* read grant on vendor banking data. Every system is green on its own: UC allowed the read, Okta passed MFA, EDR saw a CSV, DLP was in monitor mode. The question isn't 'was access allowed?' It's **'authorized access, unauthorized movement?'** And we must not assume Alex did it."

Four questions drive the demo: **who accessed · was it unusual · did it move · what's the evidence**.

## Scene 2 — Lakeflow: ingest (3 min)
**Click:** volume `raw_landing` (12 feeds) → pipeline `febar-e2e-access-movement` graph.
- **Databricks side:** `uc_audit`, `query_history`, `table_lineage`, shaped exactly like `system.access.audit`, `system.query.history` and `system.access.table_lineage`.
- **External side:** Okta sign-ins, CrowdStrike file events, Netskope uploads; plus HR, CMDB devices, asset registry, approved workflows, exception tickets, reporting calendar.
- **Silver:** `silver_sensitive_access` joins query history ⋈ lineage (on `statement_id`) ⋈ audit (`commandId` → source IP) ⋈ IdP session (IP → **device**) ⋈ HR ⋈ asset registry ⋈ workflow/exception/calendar. Show the expectations.
- **Gold:** `gold_access_anomalies` (Q2), `gold_exfil_chains` (Q3), `gold_incidents` + `gold_incident_timeline` (Q4).

> "Identity normalization is the hard part: the query has no device, the endpoint has no query. The source IP in the audit log is the bridge to the IdP session, and the session gives us the device."

## Scene 3 — Unity Catalog: govern (3 min)
**Click:** `treasury_vendor_bank_accounts` → tags, masks; `strategy_acquisition_forecast` → row filter; lineage graph.
- `SELECT * FROM capmarkets_stg.febar_e2e.v_live_audit_governed` — the **real** `system.access.audit` for these tables, including your own reads.
- `v_live_query_evidence` = real `system.query.history` ⋈ `system.access.table_lineage` (can lag a few hours).
- Live flip: `UPDATE capmarkets_stg.febar_e2e.gov_access_policy SET can_view_bank_details = true, can_view_forecast = true WHERE principal = current_user();` (reset to `false` afterwards).

> "Same governance surface for the business data *and* the security data. The evidence is itself governed."

## Scene 4 — ML + GenAI (3 min)
**Click:** job graph → MLflow experiment `febar_e2e_access_anomaly` → UC model `access_movement_iforest@prod`.
- Isolation Forest over 17 employee-day features spanning **identity, Databricks access, endpoint, DLP**. Explanations are given vs. department peers.
- Fusion: 60% evidence rules + 40% ML → P1–P4.
- `gold_incident_assessments`: `ai_query` (Claude Sonnet 4.6) writes the assessment with **H1 insider misuse vs H2 account/device compromise**, ATT&CK narrative, and a proportionate response. The leading-hypothesis label for Alex is **"Undetermined – needs more evidence"**. It doesn't jump to a conclusion.

## Scene 5 — Lakebase (2 min)
Synced tables in `febar_e2e_lakebase.e2e` (incidents, assessments, timeline, chains, anomalies) serve the app in milliseconds. Analyst decisions (`e2e_response.reviews`, `actions`, `events`) are OLTP writes with the analyst's identity.

## Scene 6 — The app (5 min)
1. **Incidents:** KPIs (1 P1 · 1 unauthorized movement · 1 explained by exception), the four-question funnel, and the queue. Point out Priya (P4, exception) and Kevin (DLP only).
2. **Open Alex's incident:** the page answers the four questions top to bottom:
   - **Q1:** asset, sensitivity, legitimate grant *outside* the approved treasury workflow, the statement id, device `LOANER-NYC-07`.
   - **Q2:** bar chart of 480,000 vs ~7,000 (self) vs the peer median; ML drivers; how many Finance peers ever used the asset.
   - **Q3:** query → file → destination cards, with matching SHA-256 and minutes between hops.
   - **Q4:** the evidence timeline and the side-by-side **compromise / misuse / mitigating** indicators.
3. **Threat assessment** (GenAI) on the right.
4. **Analyst review → approved response:** set disposition *Needs more evidence*, approve **Preserve evidence**, **Revoke sessions and tokens** and **Isolate device**, add a note. It persists to Lakebase with your email; nothing auto-executes.
5. **Sensitive access tab:** Q1 across the company; the governed view (bank numbers masked, forecast filtered — *as you*); and live system-table evidence.
6. **Dashboard tab:** the embedded AI/BI dashboard, with one page per question and global Employee/Department/Date filters. On Q4, set Employee = Alex Morgan.

## Scene 7 — Genie (2 min)
Ask in the app or the space:
1. *Was Alex Morgan's access unusual for Alex and for Finance peers?*
2. *Did any sensitive data move to an unauthorized destination?*
3. *What evidence supports the threat assessment for Alex Morgan's incident?*
4. *Which large extracts were explained by an approved exception ticket?* → Priya / EXC-4471.

## Close (1 min)
- **Before:** four tools, four green lights, no story.
- **After:** one incident, four answered questions, two hypotheses weighed, and a reviewed, approved response, all governed in Unity Catalog.
- **Ask:** pilot on their real `system.access.audit` / `system.query.history` / `system.access.table_lineage` plus IdP, EDR and DLP feeds.

## Rehearsal checklist
- [ ] Warehouse `9d8a677b3c55b8a7` running; open the app once (Lakebase scales to zero).
- [ ] Clear review state: `databricks psql --project febar-e2e -- -c "TRUNCATE e2e_response.events, e2e_response.actions, e2e_response.reviews;"`
- [ ] `gov_access_policy` reset to `false/false`.
- [ ] Run the 4 Genie questions once.
- [ ] Other presenters need: app access, Run on the Genie space, view on the dashboard, `SELECT` on `capmarkets_stg.febar_e2e` (Genie, the dashboard and the governed views run as the viewer).
- [ ] Say up front: **all data is synthetic**; Halcyon Financial and all people are fictional.

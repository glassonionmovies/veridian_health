# HANDOFF — Build & scan the Veridian IT/Technology (CIO) aggregate layer

**Task for the receiving agent:** build the **CIO subject-area** aggregate layer — **13 tables in
`veridian_metrics`** rolled up from the `veridian_it` raw tables — then let the SQL + semantic +
docs scan into the ShareContext Knowledge Graph. Everything you need is in this folder
(`demo-data/veridian_it_metrics_code/`). This doc is the task brief; **`README.md` is the full
reference** (table list, grains, modeling rationale) — read it if anything here is unclear.

---

## What this is

A pre-aggregated **IT-management metric layer** for a CIO subject area, written into the **same
`veridian_metrics` dataset** as the clinical/financial metrics so it is a *peer* layer that
ShareContext Metric Studio reads live (each table is small; nothing scans the multi-million-row
raw). Modeled by standard IT discipline — ITSM/SRE, DORA, SecOps, ITAM/CMDB, App Portfolio
(APM/TIME), FinOps/TBM, Service Desk, DEX, Vendor — **not** by any demo narrative.

- Window: monthly **2023-06 … 2026-05** (36 months). Anchor `as_of = DATE '2026-06-04'`.
- **No GCP project hardcoded.** Reads `veridian_health.x` (the `veridian_it` raw lives in the
  `veridian_health` dataset as `it_*`), writes `veridian_metrics.y`.

The 13 tables (build numbers are the file prefixes):

| # | Table | Kind | Grain | Discipline |
|---|---|---|---|---|
| 18 | `dim_it_system` | dim | system, as_of snapshot | App Portfolio (APM/TIME) |
| 19 | `dim_it_asset` | dim | asset, as_of snapshot | Asset/CMDB (ITAM) |
| 20 | `exec_it_kpi_month` | exec | month (one row/month — board scorecard) | CIO scorecard |
| 21 | `fact_it_incident_month` | fact | month × facility × system | Incident/Availability (ITSM/SRE) |
| 22 | `fact_it_security_month` | fact | month × facility × severity | Vulnerability/Security (SecOps) |
| 23 | `fact_it_cost_month` | fact | period × facility × system × category | FinOps/TBM |
| 24 | `fact_it_servicedesk_month` | fact | month × facility | Service Desk + Change/DORA |
| 25 | `fact_it_dex_month` | fact | period × facility × department | Digital Employee Experience |
| 26 | `worklist_open_critical_vulns` | worklist | open critical/high finding | SecOps remediation |
| 27 | `worklist_eol_refresh` | worklist | EOL/stale asset or past-EOL system | ITAM refresh / APM decommission |
| 28 | `worklist_app_rationalization` | worklist | redundant-capability system | APM/TBM consolidation |
| 29 | `worklist_cloud_waste` | worklist | high-idle cloud cost line | FinOps savings |
| 30 | `worklist_vendor_renewals` | worklist | vendor with MSA renewal ≤180d | Vendor/contract mgmt |

---

## Prerequisites

- `gcloud` + `bq` CLI installed and authenticated (`gcloud auth login`); a GCP project with
  BigQuery enabled.
- **The `veridian_it` raw tables must already exist** — build `demo-data/veridian_it/` first.
  These are the ten `veridian_health.it_*` event & inventory tables:
  `it_vendors, it_systems, it_assets, it_change_requests, it_incidents, it_vulnerabilities,
  it_cost_ledger, service_desk_tickets, clinician_ehr_usage, ai_tool_usage`.
- **The conformed base dims must already exist** — `veridian_health.facilities`,
  `veridian_health.departments`, `veridian_health.providers`. These come from the base health
  schema (`demo-data/veridian_health/` → `01_schema.sql` / `02_schema_operational.sql`).
  > Note: `facilities` and `departments` carry **`PRIMARY KEY (…) NOT ENFORCED`** — this is
  > **already declared in the base 01/02 schema** (facilities in `01_schema.sql`, departments in
  > `02_schema_operational.sql`). You do **not** add it here; the joins in this layer rely on it
  > but do not redeclare it.

---

## Build steps (run in order)

```bash
cd demo-data/veridian_it_metrics_code
export BQ_PROJECT=<PROJECT>        # or rely on the gcloud default; BQ_LOCATION defaults to US
./run_pipeline.sh                  # builds all 13 in dependency order
bq --location=US query --use_legacy_sql=false < validate_it_metrics.sql
```

`run_pipeline.sh` runs: `00_create_dataset` → dims **18, 19** → facts **21..25** →
worklists **26..30** → exec **20** (last). It reads `$BQ_PROJECT` (else the gcloud default) and
`$BQ_LOCATION` (default `US`); it errors out if no project can be resolved. **Order matters:**
- `28_worklist_app_rationalization` reads `dim_it_system`, so **18 builds before 28**.
- `20_exec_it_kpi_month` reads the five facts **and** `dim_it_system` (fleet size for the
  availability denominator), so it **builds last** — it reads the **agg layer only**, never raw.

---

## Modeling notes (so the numbers are trusted, not surprises)

- **Facts carry additive measures only** (counts, minute/cost SUMs). Ratios are divided **at read**.
  `exec_it_kpi_month` is the **one exception** that precomputes ratios — every ratio uses
  `SAFE_DIVIDE` (availability, MTTR, SLA %, change-success/failure/emergency, lead-time hours,
  vuln-SLA-breach %, run-cost %, cloud-idle %, deflection, reopen rate, EHR after-hours %, AI
  adoption %), mirroring `exec_kpi_month`. **Availability denominator = fleet systems
  (`dim_it_system`) × minutes-in-month.**
- **`fact_it_servicedesk_month` (month × facility)** rolls up **two different event grains** —
  service-desk tickets (month = `DATE_TRUNC(opened_at)`) and change requests (month =
  `DATE_TRUNC(COALESCE(implemented_at, scheduled_at))`). `it_change_requests` is **facility-less**
  (`facility_id` is NULL — changes are enterprise/system-scoped), so all change/DORA measures
  land on **`facility_id = NULL` rows**. The join is **NULL-safe** (`COALESCE(facility_id,
  '~ENT~')`) so those rows populate, and the exec sums by month so change KPIs still aggregate
  correctly. **Don't "fix" the NULL facility — it is intentional.**
- **`fact_it_dex_month` (period × facility × department)** intentionally **drops `system_id` from
  the grain**: `ai_tool_usage` has no `system_id`, so facility × department is the common
  conformed key across `clinician_ehr_usage` + `ai_tool_usage`.
- **Point-in-time asset snapshots** (patch-currency band, % EOL, open findings) live on
  **`dim_it_asset`**, not on the monthly exec.

---

## Definition of done

1. **All 13 tables non-zero.** `validate_it_metrics.sql` query (1) lists every table with its
   `COUNT(*)`; none may be 0.
2. **`exec_it_kpi_month` has exactly 36 rows** (one per month, 2023-06 … 2026-05) and
   **`change_failure_rate` is NOT NULL** for months that have changes — query (2) reports
   `months` (expect 36), `null_cfr`, and `avg_avail`. If `change_failure_rate` is NULL across
   the board, the NULL-safe service-desk join regressed — re-check **24**.

---

## Scan into the Knowledge Graph

Once the tables exist and validate, the layer is ingested into the ShareContext KG by scanning
**all three** artifact kinds together, so nothing in the CIO subject area becomes a phantom node:
- the **SQL** (the rollup DDL in `part1/` + `part2/` — table/column structure and lineage),
- the **semantic** layer (grains, disciplines, measure/ratio definitions per the modeling notes),
- the **docs** (`README.md`, `block_diagram.md`, the ER diagram, and this `HANDOFF.md`).

This makes the 13 `veridian_metrics` IT tables queryable as a peer subject area alongside the
clinical/financial metrics.

---

## Troubleshooting

- **A table is empty** → the `veridian_it` raw `it_*` table (or a base dim) it reads is missing or
  empty. Build `demo-data/veridian_it/` and confirm `facilities`/`departments`/`providers` exist,
  then re-run.
- **`exec_it_kpi_month` ≠ 36 rows** → the month spine is fixed (`GENERATE_DATE_ARRAY('2023-06-01',
  '2026-05-01', INTERVAL 1 MONTH)`); a wrong count means the file was edited or the spine LEFT
  JOINs lost rows.
- **`change_failure_rate` all NULL** → the facility-less change rows didn't land; verify the
  `COALESCE(facility_id,'~ENT~')` NULL-safe join in `24_fact_it_servicedesk_month.sql` and that
  `it_change_requests` is non-empty.
- **Join/PK errors on `facilities`/`departments`** → those dims must come from the base 01/02
  schema with `PRIMARY KEY … NOT ENFORCED`; do not redeclare them in this layer.

# veridian_it_metrics_code — IT/Technology (CIO) aggregate layer

Pre-aggregated **CIO subject-area** metrics, built from the `veridian_it` raw
tables (`veridian_health.it_*`) into the **same `veridian_metrics` dataset** as
the clinical/financial metrics — a peer layer Metric Studio reads live. Modeled
by standard IT-management discipline (ITSM/SRE, DORA, SecOps, ITAM/CMDB, App
Portfolio/TIME, FinOps/TBM, Service Desk, DEX, Vendor), **not** by any demo
narrative.

> No GCP project hardcoded. Reads `veridian_health.x`, writes `veridian_metrics.y`.
> `as_of = DATE '2026-06-04'`; monthly window 2023-06 … 2026-05.

## Tables (13)

| # | Table | Kind | Grain | Discipline |
|---|---|---|---|---|
| 18 | `dim_it_system` | dim | system, as_of | App Portfolio (APM/TIME) |
| 19 | `dim_it_asset` | dim | asset, as_of | Asset/CMDB (ITAM) |
| 20 | `exec_it_kpi_month` | exec | month | CIO board scorecard (reads agg layer only) |
| 21 | `fact_it_incident_month` | fact | month × facility × system | Incident/Availability (ITSM/SRE) |
| 22 | `fact_it_security_month` | fact | month × facility × severity | Vulnerability/Security (SecOps) |
| 23 | `fact_it_cost_month` | fact | period × facility × system × category | FinOps/TBM |
| 24 | `fact_it_servicedesk_month` | fact | month × facility | Service Desk + Change/DORA |
| 25 | `fact_it_dex_month` | fact | period × facility × department | Digital Employee Experience |
| 26 | `worklist_open_critical_vulns` | worklist | open critical/high finding | SecOps remediation queue |
| 27 | `worklist_eol_refresh` | worklist | EOL/stale asset or past-EOL system | ITAM refresh / APM decommission |
| 28 | `worklist_app_rationalization` | worklist | redundant-capability system | APM/TBM consolidation |
| 29 | `worklist_cloud_waste` | worklist | high-idle cloud cost line | FinOps savings |
| 30 | `worklist_vendor_renewals` | worklist | vendor with MSA renewal ≤180d | Vendor/contract mgmt |

## Modeling notes
- **Facts carry additive measures only**; ratios are computed at read. `exec_it_kpi_month`
  is the one exception that precomputes ratios (mirrors `exec_kpi_month`).
- **`fact_it_servicedesk_month` rolls to month × facility** (category/channel are COUNTIF
  measures). `it_change_requests` is **facility-less** (`facility_id` NULL — changes are
  enterprise/system-scoped), so change/DORA measures land on `facility_id = NULL` rows; the
  exec sums by month so they aggregate correctly. (NULL-safe join.)
- **`fact_it_dex_month` rolls to period × facility × department** (dropped `system_id` from
  grain — `ai_tool_usage` has no `system_id`).
- Point-in-time asset snapshots (patch compliance, % EOL) live on `dim_it_asset`, not the
  monthly exec.

## Run
```bash
export BQ_PROJECT=<id>            # or gcloud default; BQ_LOCATION=US
./run_pipeline.sh                 # 00 → 18,19 dims → 21..25 facts → 26..30 worklists → 20 exec
bq --location=US query --use_legacy_sql=false < validate_it_metrics.sql
```
Dependency: `28_worklist_app_rationalization` reads `dim_it_system` (build 18 first);
`20_exec_it_kpi_month` reads the facts + `dim_it_system` (build last).

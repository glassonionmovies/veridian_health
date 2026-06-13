-- ============================================================================
--  exec_it_kpi_month   (CIO / board scorecard — one row per month)
--  Grain : month (system-wide), 2023-06 … 2026-05
--  Source: AGG LAYER ONLY — fact_it_incident_month, fact_it_security_month,
--          fact_it_cost_month, fact_it_servicedesk_month, fact_it_dex_month,
--          dim_it_system (fleet size for availability). No raw scan.
--  Powers: the CIO Executive Scorecard dashboard (one headline KPI per IT
--          discipline: reliability, security, change/DORA, FinOps, desk, DEX).
-- ----------------------------------------------------------------------------
--  Wave-2 EXCEPTION: this is the one table that precomputes RATIOS (the others
--  store additive measures and divide at read), exactly like exec_kpi_month.
--  All ratios use SAFE_DIVIDE. Availability denominator = fleet systems ×
--  minutes-in-month (fleet = COUNT(*) dim_it_system). Pure point-in-time asset
--  snapshots (patch compliance, % EOL) are NOT monthly — they live on
--  dim_it_asset, not here.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.exec_it_kpi_month`
PARTITION BY month
AS
WITH
fleet AS (SELECT COUNT(*) AS n_systems FROM `veridian_metrics.dim_it_system`),
spine AS (
  SELECT m AS month
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2023-06-01', DATE '2026-05-01', INTERVAL 1 MONTH)) AS m
),
inc AS (
  SELECT month,
    SUM(incident_count)            AS incident_count,
    SUM(sev1_count)                AS major_incident_count,
    SUM(resolution_minutes_sum)    AS resolution_minutes_sum,
    SUM(resolved_count)            AS resolved_count,
    SUM(within_sla_count)          AS incident_within_sla,
    SUM(downtime_minutes_sum)      AS downtime_minutes_sum,
    SUM(clinical_downtime_minutes) AS clinical_downtime_minutes
  FROM `veridian_metrics.fact_it_incident_month` GROUP BY month
),
sec AS (
  SELECT month,
    SUM(open_critical_eom)                          AS open_critical_vulns,
    SUM(sla_breached_count)                         AS vuln_sla_breached,
    SUM(within_sla_count) + SUM(sla_breached_count) AS vuln_sla_decided
  FROM `veridian_metrics.fact_it_security_month` GROUP BY month
),
cost AS (
  SELECT period AS month,
    SUM(total_cost)      AS it_spend_total,
    SUM(run_cost)        AS run_cost,
    SUM(cloud_cost)      AS cloud_cost,
    SUM(cloud_idle_cost) AS cloud_idle_cost
  FROM `veridian_metrics.fact_it_cost_month` GROUP BY period
),
desk AS (
  SELECT month,
    SUM(ticket_count)                 AS ticket_count,
    SUM(resolved_count)               AS desk_resolved,
    SUM(resolution_minutes_sum)       AS desk_resolution_minutes,
    SUM(self_service_count)           AS self_service_count,
    SUM(reopened_count)               AS reopened_count,
    SUM(change_total)                 AS change_total,
    SUM(change_success_count)         AS change_success,
    SUM(change_failed_count)          AS change_failed,
    SUM(change_emergency_count)       AS change_emergency,
    SUM(change_lead_time_minutes_sum) AS change_lead_minutes
  FROM `veridian_metrics.fact_it_servicedesk_month` GROUP BY month
),
dex AS (
  SELECT period AS month,
    SUM(total_ehr_minutes_sum)   AS ehr_minutes,
    SUM(after_hours_minutes_sum) AS after_hours_minutes,
    SUM(ai_minutes_saved_sum)    AS ai_minutes_saved,
    SUM(adopting_provider_count) AS ai_adopters,
    SUM(active_providers)        AS active_providers
  FROM `veridian_metrics.fact_it_dex_month` GROUP BY period
)
SELECT
  s.month,
  -- Reliability / Availability (ITSM / SRE)
  1 - SAFE_DIVIDE(inc.downtime_minutes_sum,
        f.n_systems * DATE_DIFF(DATE_ADD(s.month, INTERVAL 1 MONTH), s.month, DAY) * 1440)
                                                       AS service_availability_pct,
  COALESCE(inc.major_incident_count, 0)                AS major_incident_count,
  SAFE_DIVIDE(inc.resolution_minutes_sum, inc.resolved_count) AS mttr_minutes,
  SAFE_DIVIDE(inc.incident_within_sla, inc.incident_count)    AS incident_sla_pct,
  COALESCE(inc.clinical_downtime_minutes, 0)           AS clinical_downtime_minutes,
  -- Change / Release (DORA)
  SAFE_DIVIDE(desk.change_success, desk.change_total)  AS change_success_rate,
  SAFE_DIVIDE(desk.change_failed,  desk.change_total)  AS change_failure_rate,
  SAFE_DIVIDE(desk.change_emergency, desk.change_total) AS change_emergency_pct,
  SAFE_DIVIDE(desk.change_lead_minutes, desk.change_total) / 60 AS change_lead_time_hours,
  -- Security / Vulnerability (SecOps)
  COALESCE(sec.open_critical_vulns, 0)                 AS open_critical_vulns,
  SAFE_DIVIDE(sec.vuln_sla_breached, sec.vuln_sla_decided) AS vuln_sla_breach_pct,
  -- IT Financial / FinOps (TBM)
  COALESCE(cost.it_spend_total, CAST(0 AS NUMERIC))    AS it_spend_total,
  SAFE_DIVIDE(cost.run_cost, cost.it_spend_total)      AS run_cost_pct,
  SAFE_DIVIDE(cost.cloud_idle_cost, cost.cloud_cost)   AS cloud_idle_pct,
  -- Service Desk (ITSM)
  SAFE_DIVIDE(desk.desk_resolution_minutes, desk.desk_resolved) / 60 AS service_desk_mttr_hours,
  SAFE_DIVIDE(desk.self_service_count, desk.ticket_count) AS self_service_deflection_pct,
  SAFE_DIVIDE(desk.reopened_count, desk.desk_resolved)    AS reopen_rate,
  -- Digital Employee Experience + AI
  SAFE_DIVIDE(dex.after_hours_minutes, dex.ehr_minutes) AS ehr_after_hours_pct,
  COALESCE(dex.ai_minutes_saved, 0)                     AS ai_minutes_saved,
  SAFE_DIVIDE(dex.ai_adopters, dex.active_providers)    AS ai_adoption_pct
FROM spine s
CROSS JOIN fleet f
LEFT JOIN inc  ON inc.month  = s.month
LEFT JOIN sec  ON sec.month  = s.month
LEFT JOIN cost ON cost.month = s.month
LEFT JOIN desk ON desk.month = s.month
LEFT JOIN dex  ON dex.month  = s.month;

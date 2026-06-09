-- ============================================================================
--  exec_kpi_month   (Executive Scorecard rollup)
--  Grain : month  (1 row per month, system-wide)
--  Source: fact_revenue_cycle_month, fact_workforce_month,
--          fact_throughput_month, fact_quality_month, fact_supply_month,
--          fact_charge_capture_day   ← reads the AGG layer, never raw
--  Powers: metrics 1–10 (D1 Executive Scorecard tiles)
-- ----------------------------------------------------------------------------
--  RUN AFTER 01–06. This is the only Wave-2 job (depends on the facts).
--  Stores the headline ratios directly so the most-viewed (mobile) board
--  refreshes from a ~70-row table.
--   1 operating_margin_proxy  (supply-inclusive, via fact_supply_month)
--   2 net_patient_revenue     5 ar_days_proxy        8 alos
--   3 net_realization_pct     6 agency_pct           9 ed_boarding_avg
--   4 denial_rate             7 labor_cost_per_hr    10 serious_safety_events
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.exec_kpi_month`
PARTITION BY month
AS
WITH rcm AS (
  SELECT month,
         SUM(total_paid)    AS net_patient_revenue,
         SUM(total_billed)  AS total_billed,
         SUM(denied_claims) AS denied_claims,
         SUM(total_claims)  AS total_claims
  FROM `veridian_metrics.fact_revenue_cycle_month`
  GROUP BY month
),
wf AS (
  SELECT month,
         SUM(total_labor_cost) AS total_labor_cost,
         SUM(worked_hours)     AS worked_hours,
         SUM(agency_hours)     AS agency_hours
  FROM `veridian_metrics.fact_workforce_month`
  GROUP BY month
),
sp AS (
  SELECT month, SUM(total_supply_cost) AS total_supply_cost
  FROM `veridian_metrics.fact_supply_month`
  GROUP BY month
),
tp AS (
  SELECT month,
         SUM(ip_los_sum)        AS ip_los_sum,
         SUM(ip_discharges)     AS ip_discharges,
         SUM(ed_boarding_sum)   AS ed_boarding_sum,
         SUM(ed_boarding_events) AS ed_boarding_events,
         SUM(encounters)        AS encounters
  FROM `veridian_metrics.fact_throughput_month`
  GROUP BY month
),
ql AS (
  SELECT month, SUM(serious_safety_events) AS serious_safety_events
  FROM `veridian_metrics.fact_quality_month`
  GROUP BY month
),
cc AS (
  -- Days-in-AR proxy: 30 × (1 − collected/billed) over the month's claim flow.
  SELECT DATE_TRUNC(day, MONTH) AS month,
         SAFE_DIVIDE(SUM(claims_paid_amount), SUM(claims_billed_amount)) AS collected_ratio
  FROM `veridian_metrics.fact_charge_capture_day`
  GROUP BY month
),
months AS (SELECT month FROM rcm)
SELECT
  m.month,
  -- 1
  SAFE_DIVIDE(rcm.net_patient_revenue - wf.total_labor_cost - sp.total_supply_cost,
              rcm.net_patient_revenue)                                   AS operating_margin_proxy,
  -- 2
  rcm.net_patient_revenue,
  -- 3
  SAFE_DIVIDE(rcm.net_patient_revenue, rcm.total_billed)                 AS net_realization_pct,
  -- 4
  SAFE_DIVIDE(rcm.denied_claims, rcm.total_claims)                       AS denial_rate,
  -- 5
  30.0 * (1 - COALESCE(cc.collected_ratio, 0))                          AS ar_days_proxy,
  -- 6
  SAFE_DIVIDE(wf.agency_hours, wf.worked_hours)                          AS agency_pct,
  -- 7
  SAFE_DIVIDE(wf.total_labor_cost, CAST(wf.worked_hours AS NUMERIC))     AS labor_cost_per_worked_hour,
  -- 8
  SAFE_DIVIDE(tp.ip_los_sum, tp.ip_discharges)                          AS alos,
  -- 9
  SAFE_DIVIDE(tp.ed_boarding_sum, tp.ed_boarding_events)                AS ed_boarding_avg,
  -- 10
  ql.serious_safety_events                                              AS serious_safety_events,
  SAFE_DIVIDE(ql.serious_safety_events, tp.encounters) * 1000           AS serious_safety_rate_per_1k,
  -- supporting raw rollups (handy for breakdowns / audit)
  rcm.total_billed,
  wf.total_labor_cost,
  sp.total_supply_cost,
  tp.encounters
FROM months m
LEFT JOIN rcm ON m.month = rcm.month
LEFT JOIN wf  ON m.month = wf.month
LEFT JOIN sp  ON m.month = sp.month
LEFT JOIN tp  ON m.month = tp.month
LEFT JOIN ql  ON m.month = ql.month
LEFT JOIN cc  ON m.month = cc.month;

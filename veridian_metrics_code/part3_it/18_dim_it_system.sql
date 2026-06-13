-- ============================================================================
--  dim_it_system   (current-snapshot dimension; one row per IT system)
--  Grain : one row per system_id, as_of snapshot
--  Source: it_systems, it_vendors, it_cost_ledger (TTM run cost),
--          it_incidents (TTM reliability)
--  Powers: application-rationalization (TIME quadrant), EOL/lifecycle risk,
--          run-cost concentration, capability redundancy
-- ----------------------------------------------------------------------------
--  TTM = trailing 12 months from the fixed demo anchor (as_of 2026-06-04).
--  Additive measures only (counts, SUM run cost); ratios/ranking at read time.
--  capability_redundancy_count is COUNT(*) OVER capability across all systems;
--  is_redundant ⇒ another live system covers the same capability.
--  time_class is a deterministic TIME-quadrant assignment (TOLERATE/INVEST/
--  MIGRATE/ELIMINATE) over EOL state, tier, redundancy and run-cost size.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.dim_it_system`
CLUSTER BY system_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
cost AS (
  SELECT
    cl.system_id,
    SUM(cl.amount) AS run_cost_ttm
  FROM `veridian_health.it_cost_ledger` cl, params p
  WHERE cl.system_id IS NOT NULL
    AND cl.period > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
    AND cl.period <= p.as_of
  GROUP BY cl.system_id
),
inc AS (
  SELECT
    i.system_id,
    COUNT(*)                          AS incident_count_ttm,
    COUNTIF(i.severity = 'SEV1')      AS sev1_count_ttm
  FROM `veridian_health.it_incidents` i, params p
  WHERE i.system_id IS NOT NULL
    AND DATE(i.opened_at) > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
    AND DATE(i.opened_at) <= p.as_of
  GROUP BY i.system_id
),
-- Layer 1: passthrough + EOL state + TTM measures coalesced to 0.
base AS (
  SELECT
    s.system_id,
    s.system_name,
    s.vendor_id,
    v.vendor_name,
    s.category,
    s.capability,
    s.criticality,
    s.hosting,
    s.emr_affinity,
    s.owning_facility_id,
    s.go_live_date,
    s.end_of_life_date,
    s.annual_cost,
    s.end_of_life_date IS NOT NULL
      AND s.end_of_life_date <= p.as_of                       AS is_eol,
    s.criticality LIKE 'TIER1%'                               AS is_tier1,
    CASE
      WHEN s.end_of_life_date IS NULL THEN 'NONE'
      WHEN s.end_of_life_date <= p.as_of THEN 'PAST_EOL'
      WHEN DATE_DIFF(s.end_of_life_date, p.as_of, MONTH) <= 12 THEN '<=12M'
      WHEN DATE_DIFF(s.end_of_life_date, p.as_of, MONTH) <= 24 THEN '<=24M'
      ELSE '>24M'
    END                                                      AS eol_horizon_band,
    COALESCE(cost.run_cost_ttm, CAST(0 AS NUMERIC))          AS run_cost_ttm,
    COALESCE(inc.incident_count_ttm, 0)                      AS incident_count_ttm,
    COALESCE(inc.sev1_count_ttm, 0)                          AS sev1_count_ttm
  FROM `veridian_health.it_systems` s
  CROSS JOIN params p
  LEFT JOIN `veridian_health.it_vendors` v ON s.vendor_id = v.vendor_id
  LEFT JOIN cost ON s.system_id = cost.system_id
  LEFT JOIN inc  ON s.system_id = inc.system_id
),
-- Layer 2: capability-redundancy window across all systems + run-cost band.
windowed AS (
  SELECT
    b.*,
    COUNT(*) OVER (PARTITION BY b.capability) AS capability_redundancy_count
  FROM base b
)
SELECT
  w.system_id,
  w.system_name,
  w.vendor_id,
  w.vendor_name,
  w.category,
  w.capability,
  w.criticality,
  w.hosting,
  w.emr_affinity,
  w.owning_facility_id,
  w.go_live_date,
  w.end_of_life_date,
  w.annual_cost,
  w.is_eol,
  w.eol_horizon_band,
  w.capability_redundancy_count,
  w.capability_redundancy_count > 1                           AS is_redundant,
  w.run_cost_ttm,
  CASE
    WHEN w.run_cost_ttm > 5000000 THEN '>5M'
    WHEN w.run_cost_ttm >= 1000000 THEN '1-5M'
    ELSE '<1M'
  END                                                         AS run_cost_band,
  w.incident_count_ttm,
  w.sev1_count_ttm,
  w.is_tier1,
  -- Deterministic TIME quadrant. EOL + redundant low-criticality ⇒ retire;
  -- EOL but mission-critical ⇒ MIGRATE; high run-cost low-tier ⇒ ELIMINATE;
  -- tier1 keepers ⇒ INVEST; everything else ⇒ TOLERATE.
  CASE
    WHEN w.is_eol AND w.capability_redundancy_count > 1 AND NOT w.is_tier1 THEN 'ELIMINATE'
    WHEN w.is_eol AND w.is_tier1                                            THEN 'MIGRATE'
    WHEN w.is_eol                                                          THEN 'MIGRATE'
    WHEN NOT w.is_tier1 AND w.capability_redundancy_count > 1
         AND w.run_cost_ttm > 5000000                                      THEN 'ELIMINATE'
    WHEN w.is_tier1                                                        THEN 'INVEST'
    ELSE 'TOLERATE'
  END                                                         AS time_class
FROM windowed w;

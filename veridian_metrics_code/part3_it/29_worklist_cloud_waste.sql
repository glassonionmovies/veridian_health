-- ============================================================================
--  worklist_cloud_waste   (one row per recent CLOUD cost line with high idle %)
--  Grain : cost line (cost_id) — recent CLOUD spend, idle >= 20%
--  Source: it_cost_ledger, it_systems, it_vendors
--  Powers: FinOps / IT cost-optimization — actionable cloud waste recovery
-- ----------------------------------------------------------------------------
--  Surfaces CLOUD cost lines from the last 3 months with cloud_idle_pct >= 0.20.
--  monthly_idle_amount and annualized_savings are derived from the line's own
--  additive amount (a recoverable-dollar estimate, not a stored ratio).
--  No ORDER BY: BQ forbids ORDER BY + CLUSTER BY in a CTAS; ranked at read time.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_cloud_waste`
CLUSTER BY system_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of)
SELECT
  cl.cost_id,
  cl.system_id,
  s.system_name,
  v.vendor_name,
  cl.facility_id,
  cl.period,
  cl.amount                                            AS cloud_cost,
  cl.cloud_idle_pct,
  cl.amount * cl.cloud_idle_pct                        AS monthly_idle_amount,
  cl.amount * cl.cloud_idle_pct * 12                   AS annualized_savings,
  s.owning_facility_id                                 AS owner_facility
FROM `veridian_health.it_cost_ledger` cl
CROSS JOIN params p
LEFT JOIN `veridian_health.it_systems` s ON cl.system_id = s.system_id
LEFT JOIN `veridian_health.it_vendors` v ON cl.vendor_id = v.vendor_id
WHERE cl.cost_category = 'CLOUD'
  AND cl.cloud_idle_pct >= 0.20
  AND cl.period >= DATE_SUB(p.as_of, INTERVAL 3 MONTH);
-- (No ORDER BY: ranked at read time by annualized_savings; BQ forbids ORDER BY + CLUSTER BY in CTAS.)

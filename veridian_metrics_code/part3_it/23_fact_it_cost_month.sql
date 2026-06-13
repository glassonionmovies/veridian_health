-- ============================================================================
--  fact_it_cost_month
--  Grain : period × facility × system × cost_category
--  Source: it_cost_ledger, it_systems, it_vendors
--  Powers: IT run-vs-grow spend, cloud-waste %, license/run cost ; CIO TCO KPIs
-- ----------------------------------------------------------------------------
--  period is taken directly from it_cost_ledger.period (already a DATE month);
--  the ledger alone defines this grain, so no month spine / GENERATE_DATE_ARRAY
--  is needed (single fact source — every key is present on every ledger row).
--  cost_category is ON-GRAIN, so each conditional run/grow/cloud/license sum is
--  just that row's amount for its category — intended, kept additive.
--  cloud_idle_cost is PRE-MULTIPLIED (amount * cloud_idle_pct) so cloud-waste %
--  is computed at READ time = SUM(cloud_idle_cost) / SUM(cloud_cost). All ratios
--  are read-time; this fact stores ADDITIVE measures only. vendor_id/system_name/
--  vendor_name carried for descriptive context via LEFT JOIN (may be NULL if a
--  ledger row references a system/vendor absent from the dim).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_it_cost_month`
PARTITION BY period
CLUSTER BY system_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
ledger AS (
  SELECT
    cl.period,
    cl.facility_id,
    cl.system_id,
    cl.vendor_id,
    cl.cost_category,
    SUM(cl.amount)                                                               AS total_cost,
    SUM(IF(cl.cost_category IN ('LICENSE','SUPPORT','CLOUD','LABOR','TELECOM'),
           cl.amount, CAST(0 AS NUMERIC)))                                       AS run_cost,
    SUM(IF(cl.cost_category = 'HARDWARE', cl.amount, CAST(0 AS NUMERIC)))        AS grow_cost,
    SUM(IF(cl.cost_category = 'CLOUD',   cl.amount, CAST(0 AS NUMERIC)))         AS cloud_cost,
    SUM(IF(cl.cost_category = 'CLOUD',
           cl.amount * COALESCE(cl.cloud_idle_pct, 0), CAST(0 AS NUMERIC)))      AS cloud_idle_cost,
    SUM(IF(cl.cost_category = 'LICENSE', cl.amount, CAST(0 AS NUMERIC)))         AS license_cost,
    COUNT(*)                                                                     AS cost_line_count
  FROM `veridian_health.it_cost_ledger` cl
  GROUP BY cl.period, cl.facility_id, cl.system_id, cl.vendor_id, cl.cost_category
)
SELECT
  l.period,
  l.facility_id,
  l.system_id,
  s.system_name,
  l.vendor_id,
  v.vendor_name,
  l.cost_category,
  COALESCE(l.total_cost,      CAST(0 AS NUMERIC)) AS total_cost,
  COALESCE(l.run_cost,        CAST(0 AS NUMERIC)) AS run_cost,
  COALESCE(l.grow_cost,       CAST(0 AS NUMERIC)) AS grow_cost,
  COALESCE(l.cloud_cost,      CAST(0 AS NUMERIC)) AS cloud_cost,
  COALESCE(l.cloud_idle_cost, CAST(0 AS NUMERIC)) AS cloud_idle_cost,
  COALESCE(l.license_cost,    CAST(0 AS NUMERIC)) AS license_cost,
  COALESCE(l.cost_line_count, 0)                  AS cost_line_count
FROM ledger l
LEFT JOIN `veridian_health.it_systems` s ON l.system_id = s.system_id
LEFT JOIN `veridian_health.it_vendors` v ON l.vendor_id = v.vendor_id;

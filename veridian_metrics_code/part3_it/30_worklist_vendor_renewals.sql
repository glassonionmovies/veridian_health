-- ============================================================================
--  worklist_vendor_renewals   (vendors with an MSA renewal coming due)
--  Grain : one row per vendor with msa_renewal_date within ~180d of as_of
--  Source: it_vendors, it_systems, it_cost_ledger
--  Powers: IT vendor-management / contract-renewal worklist; sourcing &
--          concentration-risk review ahead of MSA renewal.
-- ----------------------------------------------------------------------------
--  ttm_spend rolls it_cost_ledger.amount over the trailing 12 months by
--  vendor_id (ledger rows with NULL vendor_id, e.g. LABOR, are not vendor-
--  attributable and fall out). is_sole_source is a concentration PROXY
--  (>=2 systems under a strategic vendor), not a contractual sole-source flag.
-- ============================================================================
CREATE OR REPLACE TABLE `veridian_metrics.worklist_vendor_renewals`
CLUSTER BY msa_renewal_date AS
WITH params AS (
  SELECT DATE '2026-06-04' AS as_of
),
sys AS (
  SELECT
    vendor_id,
    COUNT(*) AS systems_under_vendor
  FROM `veridian_health.it_systems`
  GROUP BY vendor_id
),
ttm AS (
  SELECT
    cl.vendor_id,
    SUM(cl.amount) AS ttm_spend
  FROM `veridian_health.it_cost_ledger` cl
  CROSS JOIN params p
  WHERE cl.vendor_id IS NOT NULL
    AND cl.period >  DATE_SUB(p.as_of, INTERVAL 12 MONTH)
    AND cl.period <= p.as_of
  GROUP BY cl.vendor_id
)
SELECT
  v.vendor_id,
  v.vendor_name,
  v.category,
  v.is_strategic,
  v.msa_renewal_date,
  DATE_DIFF(v.msa_renewal_date, p.as_of, DAY)        AS days_to_renewal,
  v.annual_spend,
  COALESCE(ttm.ttm_spend, CAST(0 AS NUMERIC))        AS ttm_spend,
  COALESCE(sys.systems_under_vendor, 0)              AS systems_under_vendor,
  (COALESCE(sys.systems_under_vendor, 0) >= 2
     AND v.is_strategic)                             AS is_sole_source
FROM `veridian_health.it_vendors` v
CROSS JOIN params p
LEFT JOIN sys USING (vendor_id)
LEFT JOIN ttm USING (vendor_id)
WHERE v.msa_renewal_date BETWEEN p.as_of AND DATE_ADD(p.as_of, INTERVAL 180 DAY)
GROUP BY
  v.vendor_id,
  v.vendor_name,
  v.category,
  v.is_strategic,
  v.msa_renewal_date,
  p.as_of,
  v.annual_spend,
  ttm.ttm_spend,
  sys.systems_under_vendor;

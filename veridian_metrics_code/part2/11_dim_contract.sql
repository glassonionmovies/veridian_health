-- ============================================================================
--  dim_contract   (current-snapshot dimension)
--  Source: payer_contracts, payers, claims (TTM)
--  Powers: metrics 18 (expiring-contract exposure), 19 (timely filing)
-- ----------------------------------------------------------------------------
--  days_to_expiry is relative to the fixed demo anchor (as_of 2026-06-04);
--  negative ⇒ already expired (still billed against = the planted error).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.dim_contract`
CLUSTER BY payer_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
clm AS (
  SELECT
    c.contract_id,
    COUNT(*)                   AS claims_ttm,
    SUM(c.total_billed_amount) AS billed_ttm
  FROM `veridian_health.claims` c, params p
  WHERE DATE(c.submission_datetime) > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY c.contract_id
)
SELECT
  pc.contract_id,
  pc.payer_id,
  pay.payer_name,
  pc.plan_subtype,
  pc.reimbursement_methodology,
  pc.baseline_multiplier,
  pc.effective_date,
  pc.expiration_date,
  pc.appeal_window_days,
  pc.timely_filing_days,
  DATE_DIFF(pc.expiration_date, p.as_of, DAY) AS days_to_expiry,
  COALESCE(clm.claims_ttm, 0)                 AS claims_ttm,
  clm.billed_ttm
FROM `veridian_health.payer_contracts` pc
CROSS JOIN params p
LEFT JOIN `veridian_health.payers` pay ON pc.payer_id = pay.payer_id
LEFT JOIN clm ON pc.contract_id = clm.contract_id;

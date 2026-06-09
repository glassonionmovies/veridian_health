-- ============================================================================
--  dim_payer   (current-snapshot dimension)
--  Source: payers, payer_contracts, claims (TTM)
--  Powers: metrics 11 (denial rate by payer), 16, 17 (yield)
-- ----------------------------------------------------------------------------
--  TTM = trailing 12 months from the fixed demo anchor (as_of 2026-06-04).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.dim_payer`
CLUSTER BY payer_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
ttm AS (
  SELECT
    c.payer_id,
    COUNT(*)                            AS total_claims_ttm,
    COUNTIF(c.claim_status = 'DENIED')  AS denied_claims_ttm,
    SUM(c.total_billed_amount)          AS billed_ttm,
    SUM(c.total_allowed_amount)         AS allowed_ttm,
    SUM(c.total_paid_amount)            AS paid_ttm
  FROM `veridian_health.claims` c, params p
  WHERE DATE(c.submission_datetime) > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY c.payer_id
),
ct AS (
  SELECT
    payer_id,
    COUNT(*)                  AS contract_versions,
    AVG(baseline_multiplier)  AS avg_baseline_multiplier,
    MIN(expiration_date)      AS earliest_expiration
  FROM `veridian_health.payer_contracts`
  GROUP BY payer_id
)
SELECT
  p.payer_id,
  p.payer_name,
  p.payer_type,
  COALESCE(ct.contract_versions, 0)                          AS contract_versions,
  ct.avg_baseline_multiplier,
  ct.earliest_expiration,
  COALESCE(ttm.total_claims_ttm, 0)                          AS total_claims_ttm,
  SAFE_DIVIDE(ttm.denied_claims_ttm, ttm.total_claims_ttm)   AS denial_rate_ttm,
  SAFE_DIVIDE(ttm.paid_ttm, ttm.allowed_ttm)                 AS contract_yield_ttm,
  ttm.billed_ttm,
  ttm.paid_ttm
FROM `veridian_health.payers` p
LEFT JOIN ct  ON p.payer_id = ct.payer_id
LEFT JOIN ttm ON p.payer_id = ttm.payer_id;

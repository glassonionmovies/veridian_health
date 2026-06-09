-- ============================================================================
--  fact_revenue_cycle_month
--  Grain : month × payer × contract   (claims-side rows)
--          UNION month × payer        (appeals-side rows, contract_id = NULL)
--  Source: claims, appeals_history, payer_contracts, payers
--  Powers: metrics 2,3,4,11–19 ; feeds exec_kpi_month
-- ----------------------------------------------------------------------------
--  WHY THE UNION: appeals_history has NO contract_id and is NOT linked to
--  claims by claim_id (NULL by design — joined to payers by payer_id only).
--  So appeals cannot be attributed to a contract without double-counting.
--  We keep ONE table by emitting appeals as separate rows (contract_id NULL)
--  with all claims-measures = 0, and claims rows with all appeals-measures = 0.
--  Every metric is then a plain SUM():
--     denial_rate  = SUM(denied_claims)  / NULLIF(SUM(total_claims),0)
--     win_rate     = SUM(appeals_won)    / NULLIF(SUM(appeals_decided),0)
--  …with no cross-contamination (the inapplicable side contributes 0).
--
--  ASSUMPTIONS to reconcile against demo-data/.../validate.sql when first run:
--   • underpayment_dollars = allowed − paid for PAID claims paid >5% below the
--     contractually-allowed amount (matches validate.sql underpayment_uhc_220 /
--     _360k: status='PAID', paid < allowed*0.95 → planted UHC DRG-470 ≈ $360K/220).
--   • appeals_decided = WON|PARTIAL_WON|LOST (excludes PENDING / timed-out);
--     planted win rate = 22/30 = 73%.
--  as_of is the fixed demo anchor (AS_OF_DATE 2026-06-04), never wall-clock.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_revenue_cycle_month`
PARTITION BY month
CLUSTER BY payer_id, contract_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
claims_agg AS (
  SELECT
    DATE_TRUNC(DATE(c.submission_datetime), MONTH)                       AS month,
    c.payer_id,
    ANY_VALUE(c.payer_name)                                             AS payer_name,
    c.contract_id,
    COUNT(*)                                                            AS total_claims,
    SUM(c.total_billed_amount)                                          AS total_billed,
    SUM(c.total_allowed_amount)                                         AS total_allowed,
    SUM(c.total_paid_amount)                                            AS total_paid,
    COUNTIF(c.claim_status = 'DENIED')                                  AS denied_claims,
    SUM(IF(c.claim_status = 'DENIED', c.total_billed_amount, CAST(0 AS NUMERIC)))                AS denied_billed,
    SUM(IF(c.claim_status = 'PAID'
           AND c.total_paid_amount < c.total_allowed_amount * 0.95,
           c.total_allowed_amount - c.total_paid_amount, CAST(0 AS NUMERIC)))                    AS underpayment_dollars,
    COUNTIF(c.claim_status = 'DENIED'
            AND (c.appeal_status IS NULL OR c.appeal_status = 'NOT_APPEALED')
            AND c.denial_datetime IS NOT NULL
            AND DATE_DIFF(DATE_ADD(DATE(c.denial_datetime), INTERVAL pc.appeal_window_days DAY),
                          (SELECT as_of FROM params), DAY) BETWEEN 0 AND 15)                     AS timely_filing_at_risk
  FROM `veridian_health.claims` c
  LEFT JOIN `veridian_health.payer_contracts` pc ON c.contract_id = pc.contract_id
  GROUP BY month, c.payer_id, c.contract_id
),
appeals_agg AS (
  SELECT
    DATE_TRUNC(DATE(a.decision_datetime), MONTH)                        AS month,
    a.payer_id,
    ANY_VALUE(pay.payer_name)                                          AS payer_name,
    CAST(NULL AS STRING)                                               AS contract_id,
    COUNTIF(a.outcome IN ('WON','PARTIAL_WON','LOST'))                 AS appeals_decided,
    COUNTIF(a.outcome IN ('WON','PARTIAL_WON'))                        AS appeals_won,
    SUM(a.recovered_amount)                                            AS recovered_amount
  FROM `veridian_health.appeals_history` a
  LEFT JOIN `veridian_health.payers` pay ON a.payer_id = pay.payer_id
  WHERE a.decision_datetime IS NOT NULL
  GROUP BY month, a.payer_id
)
SELECT
  month, payer_id, payer_name, contract_id,
  total_claims, total_billed, total_allowed, total_paid,
  denied_claims, denied_billed, underpayment_dollars, timely_filing_at_risk,
  0                  AS appeals_decided,
  0                  AS appeals_won,
  CAST(0 AS NUMERIC) AS recovered_amount
FROM claims_agg
UNION ALL
SELECT
  month, payer_id, payer_name, contract_id,
  0                  AS total_claims,
  CAST(0 AS NUMERIC) AS total_billed,
  CAST(0 AS NUMERIC) AS total_allowed,
  CAST(0 AS NUMERIC) AS total_paid,
  0                  AS denied_claims,
  CAST(0 AS NUMERIC) AS denied_billed,
  CAST(0 AS NUMERIC) AS underpayment_dollars,
  0                  AS timely_filing_at_risk,
  appeals_decided, appeals_won, recovered_amount
FROM appeals_agg;

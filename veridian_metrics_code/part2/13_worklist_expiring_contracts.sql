-- ============================================================================
--  worklist_expiring_contracts   (one row per at-risk contract)
--  Source: payer_contracts, payers, claims
--  Powers: metric 18 (expiring-contract exposure; planted: 40 claims billed on
--          a terminated Aetna contract version)
-- ----------------------------------------------------------------------------
--  Surfaces contracts that are (a) expiring within 90 days of as_of, or
--  (b) already expired but STILL being billed against (service after expiry) —
--  the planted billing error. dollars_at_risk = billed on post-expiry claims.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_expiring_contracts`
CLUSTER BY payer_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of)
SELECT
  pc.contract_id,
  pc.payer_id,
  pay.payer_name,
  pc.plan_subtype,
  pc.effective_date,
  pc.expiration_date,
  DATE_DIFF(pc.expiration_date, p.as_of, DAY)                                       AS days_to_expiry,
  COUNT(c.claim_id)                                                                 AS claims_total,
  COUNTIF(c.service_date_start > pc.expiration_date)                                AS claims_after_expiry,
  SUM(IF(c.service_date_start > pc.expiration_date, c.total_billed_amount, CAST(0 AS NUMERIC))) AS dollars_billed_after_expiry
FROM `veridian_health.payer_contracts` pc
CROSS JOIN params p
LEFT JOIN `veridian_health.payers` pay ON pc.payer_id = pay.payer_id
LEFT JOIN `veridian_health.claims` c   ON c.contract_id = pc.contract_id
WHERE pc.expiration_date IS NOT NULL
  AND pc.expiration_date <= DATE_ADD(p.as_of, INTERVAL 90 DAY)
GROUP BY pc.contract_id, pc.payer_id, pay.payer_name, pc.plan_subtype,
         pc.effective_date, pc.expiration_date, days_to_expiry
HAVING claims_after_expiry > 0 OR days_to_expiry BETWEEN 0 AND 90;
-- (No ORDER BY: ranked at read time by the metric detail_sql; BQ forbids ORDER BY + CLUSTER BY in CTAS.)

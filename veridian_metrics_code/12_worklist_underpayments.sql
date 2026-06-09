-- ============================================================================
--  worklist_underpayments   (ranked detail grid — one row per underpaid claim)
--  Source: claims, payer_contracts, payers
--  Powers: metric 16 detail table (planted: UHC DRG-470 ≈ $360K / 220 claims)
-- ----------------------------------------------------------------------------
--  An underpaid claim = PAID where total_paid < total_allowed * 0.95 (>5% off
--  contract) — matches validate.sql underpayment_uhc_220 / _360k. Denials and
--  partial-pays are NOT underpayments (they'd swamp the worklist).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_underpayments`
CLUSTER BY payer_id, contract_id
AS
SELECT
  c.claim_id,
  c.payer_id,
  c.payer_name,
  c.contract_id,
  pc.plan_subtype,
  c.drg_code,
  c.cpt_code,
  c.service_date_start,
  c.total_billed_amount,
  c.total_allowed_amount,
  c.total_paid_amount,
  (c.total_allowed_amount - c.total_paid_amount)                               AS underpayment_variance,
  SAFE_DIVIDE(c.total_allowed_amount - c.total_paid_amount, c.total_allowed_amount) AS underpayment_pct
FROM `veridian_health.claims` c
LEFT JOIN `veridian_health.payer_contracts` pc ON c.contract_id = pc.contract_id
WHERE c.claim_status = 'PAID'
  AND c.total_paid_amount < c.total_allowed_amount * 0.95;
-- (No ORDER BY: BigQuery forbids ORDER BY with CLUSTER BY in CTAS. The metric
--  detail_sql ranks rows by underpayment_variance at read time.)

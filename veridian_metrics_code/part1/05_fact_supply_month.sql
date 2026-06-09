-- ============================================================================
--  fact_supply_month   ★ NEW (17th table)
--  Grain : month × facility × item_category
--  Source: supply_chain_transactions, facilities
--  Powers: supply/non-labor cost; feeds exec_kpi_month operating-margin proxy
-- ----------------------------------------------------------------------------
--  Added so Operating Margin (#1) is SUPPLY-INCLUSIVE rather than labor-only:
--     operating_margin_proxy = (net_patient_revenue − labor_cost − supply_cost)
--                              / net_patient_revenue
--  "Synthetic data" for this table is the existing synthetic raw
--  supply_chain_transactions (no generator change needed) — this job rolls it
--  up to month × facility × category.
--
--  Supply COST (COGS) = items ISSUE_TO_CASE'd to patients, net of RETURNs.
--  PO_RECEIPT is an inventory PURCHASE (not yet expensed) and is EXCLUDED from
--  total_supply_cost — counting both buy AND use double-counts spend (it was
--  inflating the operating-margin proxy ~18x labor). Receipts/waste/off-contract
--  stay in their own columns for purchasing/leakage analyses.
--  off_contract_cost backs the GPO-leakage / price-variance story.
--  extended_cost is NUMERIC in the raw table → sums stay exact.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_supply_month`
PARTITION BY month
CLUSTER BY facility_id, item_category
AS
SELECT
  DATE_TRUNC(DATE(s.transaction_datetime), MONTH)                       AS month,
  s.facility_id,
  ANY_VALUE(f.facility_name)                                          AS facility_name,
  ANY_VALUE(f.region)                                                AS region,
  s.item_category,
  COUNT(*)                                                            AS txn_count,
  SUM(s.quantity)                                                     AS total_quantity,
  -- COGS = items consumed on cases, less returns. PO_RECEIPT (inventory buy)
  -- and WASTE are EXCLUDED here (WASTE tracked separately below).
  SUM(CASE s.transaction_type
        WHEN 'ISSUE_TO_CASE' THEN s.extended_cost
        WHEN 'RETURN'        THEN -s.extended_cost
        ELSE CAST(0 AS NUMERIC) END)                                  AS total_supply_cost,
  SUM(IF(s.transaction_type = 'WASTE', s.extended_cost, CAST(0 AS NUMERIC)))      AS waste_cost,
  SUM(IF(s.is_off_contract
         AND s.transaction_type IN ('PO_RECEIPT','ISSUE_TO_CASE'),
         s.extended_cost, CAST(0 AS NUMERIC)))                        AS off_contract_cost,
  COUNTIF(s.is_off_contract)                                          AS off_contract_txns
FROM `veridian_health.supply_chain_transactions` s
LEFT JOIN `veridian_health.facilities` f ON s.facility_id = f.facility_id
GROUP BY month, s.facility_id, s.item_category;

-- ============================================================================
--  fact_charge_capture_day
--  Grain : day × facility
--  Source: charges, claims, encounters
--  Powers: metrics 5 (Days-in-AR proxy), 20 (Charge-Capture Lag)
-- ----------------------------------------------------------------------------
--  Daily grain so the charge-capture and cash-velocity metrics can trend at
--  finer resolution than the monthly facts. Facility attribution via
--  encounters.facility_id for both charges and claims.
--   • charge_lag_days = posting date − encounter admission date (POSTED charges)
--   • Days-in-AR proxy (metric 5) is derived at read/exec time from the daily
--     billed vs paid columns (no AR sub-ledger exists in the synthetic data).
--  Built from a (day, facility) spine.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_charge_capture_day`
PARTITION BY day
CLUSTER BY facility_id
AS
WITH chg AS (
  SELECT
    DATE(c.charge_datetime)                                            AS day,
    e.facility_id,
    COUNTIF(c.status = 'POSTED')                                       AS charges_posted,
    SUM(IF(c.status = 'POSTED', c.billed_amount, CAST(0 AS NUMERIC)))  AS charges_billed_amount,
    SUM(IF(c.status = 'POSTED',
           DATE_DIFF(DATE(c.charge_datetime), DATE(e.admission_datetime), DAY), 0)) AS charge_lag_days_sum,
    COUNTIF(c.status = 'POSTED'
            AND DATE_DIFF(DATE(c.charge_datetime), DATE(e.admission_datetime), DAY) > 3) AS late_charges
  FROM `veridian_health.charges` c
  JOIN `veridian_health.encounters` e ON c.encounter_id = e.encounter_id
  GROUP BY day, e.facility_id
),
clm AS (
  SELECT
    DATE(c.submission_datetime)                                        AS day,
    e.facility_id,
    COUNT(*)                                                           AS claims_submitted,
    SUM(c.total_billed_amount)                                         AS claims_billed_amount,
    SUM(c.total_paid_amount)                                           AS claims_paid_amount
  FROM `veridian_health.claims` c
  JOIN `veridian_health.encounters` e ON c.encounter_id = e.encounter_id
  GROUP BY day, e.facility_id
),
spine AS (
  SELECT day, facility_id FROM chg
  UNION DISTINCT SELECT day, facility_id FROM clm
)
SELECT
  s.day,
  s.facility_id,
  f.facility_name,
  f.region,
  COALESCE(chg.charges_posted, 0)                       AS charges_posted,
  COALESCE(chg.charges_billed_amount, CAST(0 AS NUMERIC)) AS charges_billed_amount,
  COALESCE(chg.charge_lag_days_sum, 0)                  AS charge_lag_days_sum,
  COALESCE(chg.late_charges, 0)                         AS late_charges,
  COALESCE(clm.claims_submitted, 0)                     AS claims_submitted,
  COALESCE(clm.claims_billed_amount, CAST(0 AS NUMERIC)) AS claims_billed_amount,
  COALESCE(clm.claims_paid_amount, CAST(0 AS NUMERIC))  AS claims_paid_amount
FROM spine s
LEFT JOIN `veridian_health.facilities` f ON s.facility_id = f.facility_id
LEFT JOIN chg ON s.day = chg.day AND s.facility_id = chg.facility_id
LEFT JOIN clm ON s.day = clm.day AND s.facility_id = clm.facility_id;

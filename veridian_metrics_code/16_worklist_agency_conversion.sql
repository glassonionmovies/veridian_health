-- ============================================================================
--  worklist_agency_conversion   (one row per facility × role)
--  Source: workforce_shifts, facilities
--  Powers: metric 29 (Agency→FTE conversion opportunity $; planted ≈ $18.1M)
-- ----------------------------------------------------------------------------
--  Conversion opportunity = the premium paid for agency hours vs. converting
--  them to employed hours at that role's blended employed rate:
--     fte_conversion_opportunity = agency_cost − agency_hours × employed_rate
--  employed_rate is per-role (TTM). Money math casts FLOAT64 hours → NUMERIC.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_agency_conversion`
CLUSTER BY facility_id, associate_role
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
role_rate AS (
  SELECT
    w.associate_role,
    SAFE_DIVIDE(
      SUM(IF(NOT w.is_agency, CAST(w.worked_hours AS NUMERIC) * w.hourly_cost, CAST(0 AS NUMERIC))),
      SUM(IF(NOT w.is_agency, CAST(w.worked_hours AS NUMERIC), CAST(0 AS NUMERIC)))
    ) AS employed_rate
  FROM `veridian_health.workforce_shifts` w, params p
  WHERE w.shift_date > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY w.associate_role
),
agg AS (
  SELECT
    w.facility_id,
    w.associate_role,
    SUM(IF(w.is_agency, w.worked_hours, 0.0))                                          AS agency_hours,
    SUM(IF(w.is_agency, CAST(w.worked_hours AS NUMERIC) * w.hourly_cost, CAST(0 AS NUMERIC))) AS agency_cost,
    COUNTIF(w.is_agency)                                                               AS agency_shifts
  FROM `veridian_health.workforce_shifts` w, params p
  WHERE w.shift_date > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY w.facility_id, w.associate_role
)
SELECT
  agg.facility_id,
  f.facility_name,
  f.region,
  agg.associate_role,
  agg.agency_shifts,
  agg.agency_hours,
  agg.agency_cost,
  rr.employed_rate,
  (agg.agency_cost - CAST(agg.agency_hours AS NUMERIC) * rr.employed_rate) AS fte_conversion_opportunity
FROM agg
LEFT JOIN `veridian_health.facilities` f ON agg.facility_id = f.facility_id
LEFT JOIN role_rate rr ON agg.associate_role = rr.associate_role
WHERE agg.agency_hours > 0;
-- (No ORDER BY: ranked at read time by the metric detail_sql; BQ forbids ORDER BY + CLUSTER BY in CTAS.)

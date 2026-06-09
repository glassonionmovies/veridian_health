-- ============================================================================
--  fact_workforce_month
--  Grain : month × facility × associate_role
--  Source: workforce_shifts, facilities
--  Powers: metrics 6,7,21–30 ; feeds exec_kpi_month
-- ----------------------------------------------------------------------------
--  Stores ADDITIVE components only (hours, costs, counts). Ratios (agency %,
--  cost/worked-hour, OT %) are computed at read time in the metric layer as
--  SUM()/SUM(), so they roll up correctly across any dimension.
--
--  Money math: worked_hours is FLOAT64, hourly_cost is NUMERIC — BigQuery has
--  no NUMERIC×FLOAT64 operator, so hours are CAST to NUMERIC for $ columns.
--  Planted signal: agency $149.96/hr vs employed $89.24/hr (~68% premium).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_workforce_month`
PARTITION BY month
CLUSTER BY facility_id, associate_role
AS
SELECT
  DATE_TRUNC(w.shift_date, MONTH)                                    AS month,
  w.facility_id,
  ANY_VALUE(f.facility_name)                                        AS facility_name,
  ANY_VALUE(f.region)                                               AS region,
  w.associate_role,
  COUNT(*)                                                          AS total_shifts,
  COUNTIF(w.is_agency)                                              AS agency_shifts,
  SUM(w.scheduled_hours)                                            AS scheduled_hours,
  SUM(w.worked_hours)                                               AS worked_hours,
  SUM(w.overtime_hours)                                             AS overtime_hours,
  SUM(IF(w.is_agency, w.worked_hours, 0.0))                         AS agency_hours,
  SUM(CAST(w.worked_hours AS NUMERIC) * w.hourly_cost)              AS total_labor_cost,
  SUM(IF(w.is_agency,
         CAST(w.worked_hours AS NUMERIC) * w.hourly_cost, CAST(0 AS NUMERIC)))  AS agency_cost,
  SUM(IF(NOT w.is_agency,
         CAST(w.worked_hours AS NUMERIC) * w.hourly_cost, CAST(0 AS NUMERIC)))  AS employed_cost,
  SUM(CAST(w.overtime_hours AS NUMERIC) * w.hourly_cost)            AS overtime_cost,
  AVG(w.patient_census)                                             AS avg_patient_census
FROM `veridian_health.workforce_shifts` w
LEFT JOIN `veridian_health.facilities` f ON w.facility_id = f.facility_id
GROUP BY month, w.facility_id, w.associate_role;

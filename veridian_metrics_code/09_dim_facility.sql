-- ============================================================================
--  dim_facility   (current-snapshot dimension)
--  Source: facilities, encounters (TTM volume)
--  Powers: metrics 26 (agency reliance by facility), 34 (bed occupancy)
-- ----------------------------------------------------------------------------
--  bed_capacity is carried here so the occupancy metric can be computed at read
--  time as ip_los_sum / (bed_capacity × days_in_month) against fact_throughput.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.dim_facility`
CLUSTER BY facility_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
enc AS (
  SELECT e.facility_id, COUNT(*) AS encounters_ttm
  FROM `veridian_health.encounters` e, params p
  WHERE DATE(e.admission_datetime) > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY e.facility_id
)
SELECT
  f.facility_id,
  f.facility_name,
  f.region,
  f.primary_emr,
  f.bed_capacity,
  f.is_legacy,
  COALESCE(enc.encounters_ttm, 0) AS encounters_ttm
FROM `veridian_health.facilities` f
LEFT JOIN enc ON f.facility_id = enc.facility_id;

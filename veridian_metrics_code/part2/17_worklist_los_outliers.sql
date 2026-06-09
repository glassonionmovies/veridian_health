-- ============================================================================
--  worklist_los_outliers   (one row per active over-benchmark inpatient)
--  Source: encounters, departments, providers, care_management
--  Powers: metric 32 (planted: 23 active outliers; 8 with SNF never started)
-- ----------------------------------------------------------------------------
--  Active IP (ACTIVE | PENDING_DISCHARGE) whose CURRENT length of stay
--  (as_of − admission) exceeds the DRG benchmark by > 2 days.
--  service_line is attributed via attending provider → department (encounters
--  carry no department_id). snf_request_started = a SNF placement task exists
--  and is not NOT_STARTED (the planted process gap is when it's missing).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_los_outliers`
CLUSTER BY facility_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
snf AS (
  SELECT
    encounter_id,
    LOGICAL_OR(task_type = 'SNF_PLACEMENT_REQUEST' AND task_status <> 'NOT_STARTED') AS snf_request_started
  FROM `veridian_health.care_management`
  GROUP BY encounter_id
)
SELECT
  e.encounter_id,
  e.facility_id,
  f.facility_name,
  dept.service_line,
  e.drg_code,
  e.admission_datetime,
  e.drg_benchmark_los,
  TIMESTAMP_DIFF(TIMESTAMP(p.as_of), e.admission_datetime, DAY)                        AS current_los_days,
  TIMESTAMP_DIFF(TIMESTAMP(p.as_of), e.admission_datetime, DAY) - e.drg_benchmark_los  AS excess_days,
  e.discharge_planning_status,
  COALESCE(snf.snf_request_started, FALSE)                                             AS snf_request_started
FROM `veridian_health.encounters` e
CROSS JOIN params p
LEFT JOIN `veridian_health.providers` pr
       ON e.attending_provider_npi = pr.provider_npi AND pr.is_current
LEFT JOIN `veridian_health.departments` dept ON pr.department_id = dept.department_id
LEFT JOIN `veridian_health.facilities`  f    ON e.facility_id = f.facility_id
LEFT JOIN snf ON e.encounter_id = snf.encounter_id
WHERE e.status IN ('ACTIVE','PENDING_DISCHARGE')
  AND e.drg_benchmark_los IS NOT NULL
  AND TIMESTAMP_DIFF(TIMESTAMP(p.as_of), e.admission_datetime, DAY) - e.drg_benchmark_los > 2;
-- (No ORDER BY: ranked at read time by the metric detail_sql; BQ forbids ORDER BY + CLUSTER BY in CTAS.)

-- ============================================================================
--  fact_throughput_month
--  Grain : month × facility
--  Source: encounters, bed_management, appointments_scheduling,
--          prior_authorizations, referrals, orders, patient_master_index
--  Powers: metrics 8,9,31–40 ; feeds exec_kpi_month
-- ----------------------------------------------------------------------------
--  FACILITY ATTRIBUTION (documented, because several sources lack facility_id):
--   • prior_authorizations → facility via encounters.facility_id (encounter_id)
--   • referrals            → facility via patient_master_index.primary_facility_id
--   • orders (imaging)      → facility via encounters.facility_id
--  Grain is month × FACILITY (not × department): encounters carry no
--  department_id, so a clean month×dept grain isn't derivable here. Department/
--  service-line LOS detail is in worklist_los_outliers (17). Bed-occupancy %
--  (metric 34) is computed at read time = ip_los_sum / (bed_capacity × days).
--
--  Built from a (month, facility) spine so a facility present in one source but
--  not another still gets a row (measures COALESCE to 0).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_throughput_month`
PARTITION BY month
CLUSTER BY facility_id
AS
WITH enc AS (
  SELECT
    DATE_TRUNC(DATE(admission_datetime), MONTH)                          AS month,
    facility_id,
    COUNT(*)                                                             AS encounters,
    COUNTIF(encounter_type = 'IP' AND status = 'DISCHARGED')             AS ip_discharges,
    SUM(IF(encounter_type = 'IP' AND los_days IS NOT NULL, los_days, 0.0)) AS ip_los_sum,
    SUM(IF(los_days IS NOT NULL AND drg_benchmark_los IS NOT NULL,
           GREATEST(los_days - drg_benchmark_los, 0.0), 0.0))            AS los_excess_sum
  FROM `veridian_health.encounters`
  GROUP BY month, facility_id
),
bed AS (
  SELECT
    DATE_TRUNC(DATE(assigned_datetime), MONTH)                          AS month,
    facility_id,
    SUM(IF(ed_boarding_hours IS NOT NULL, ed_boarding_hours, 0.0))      AS ed_boarding_sum,
    COUNTIF(ed_boarding_hours IS NOT NULL)                              AS ed_boarding_events,
    COUNTIF(is_blocked)                                                 AS blocked_bed_events
  FROM `veridian_health.bed_management`
  GROUP BY month, facility_id
),
appt AS (
  SELECT
    DATE_TRUNC(DATE(scheduled_datetime), MONTH)                         AS month,
    facility_id,
    COUNT(*)                                                            AS appointments,
    COUNTIF(status = 'NO_SHOW')                                         AS no_shows,
    COUNTIF(is_new_patient)                                             AS new_patient_appts
  FROM `veridian_health.appointments_scheduling`
  GROUP BY month, facility_id
),
pa AS (
  SELECT
    DATE_TRUNC(DATE(p.requested_datetime), MONTH)                       AS month,
    e.facility_id,
    COUNT(*)                                                            AS prior_auths,
    COUNTIF(p.auth_status IN ('DENIED','NOT_OBTAINED'))                 AS pa_denied,
    COUNTIF(p.decision_datetime IS NOT NULL)                            AS pa_decided,
    SUM(IF(p.decision_datetime IS NOT NULL,
           TIMESTAMP_DIFF(p.decision_datetime, p.requested_datetime, HOUR), 0)) AS pa_turnaround_hours_sum
  FROM `veridian_health.prior_authorizations` p
  JOIN `veridian_health.encounters` e ON p.encounter_id = e.encounter_id
  GROUP BY month, e.facility_id
),
ref AS (
  SELECT
    DATE_TRUNC(r.created_date, MONTH)                                   AS month,
    m.primary_facility_id                                              AS facility_id,
    COUNT(*)                                                            AS referrals_made,
    COUNTIF(NOT r.is_in_network)                                        AS referrals_out_of_network
  FROM `veridian_health.referrals` r
  JOIN `veridian_health.patient_master_index` m ON r.master_patient_id = m.master_patient_id
  GROUP BY month, m.primary_facility_id
),
img AS (
  SELECT
    DATE_TRUNC(DATE(o.order_datetime), MONTH)                           AS month,
    e.facility_id,
    COUNTIF(o.order_type = 'IMAGING')                                   AS imaging_orders
  FROM `veridian_health.orders` o
  JOIN `veridian_health.encounters` e ON o.encounter_id = e.encounter_id
  GROUP BY month, e.facility_id
),
spine AS (
  SELECT month, facility_id FROM enc
  UNION DISTINCT SELECT month, facility_id FROM bed
  UNION DISTINCT SELECT month, facility_id FROM appt
  UNION DISTINCT SELECT month, facility_id FROM pa
  UNION DISTINCT SELECT month, facility_id FROM ref
  UNION DISTINCT SELECT month, facility_id FROM img
)
SELECT
  s.month,
  s.facility_id,
  f.facility_name,
  f.region,
  COALESCE(enc.encounters, 0)                  AS encounters,
  COALESCE(enc.ip_discharges, 0)               AS ip_discharges,
  COALESCE(enc.ip_los_sum, 0.0)                AS ip_los_sum,
  COALESCE(enc.los_excess_sum, 0.0)            AS los_excess_sum,
  COALESCE(bed.ed_boarding_sum, 0.0)           AS ed_boarding_sum,
  COALESCE(bed.ed_boarding_events, 0)          AS ed_boarding_events,
  COALESCE(bed.blocked_bed_events, 0)          AS blocked_bed_events,
  COALESCE(appt.appointments, 0)               AS appointments,
  COALESCE(appt.no_shows, 0)                   AS no_shows,
  COALESCE(appt.new_patient_appts, 0)          AS new_patient_appts,
  COALESCE(pa.prior_auths, 0)                  AS prior_auths,
  COALESCE(pa.pa_denied, 0)                    AS pa_denied,
  COALESCE(pa.pa_decided, 0)                   AS pa_decided,
  COALESCE(pa.pa_turnaround_hours_sum, 0)      AS pa_turnaround_hours_sum,
  COALESCE(ref.referrals_made, 0)              AS referrals_made,
  COALESCE(ref.referrals_out_of_network, 0)    AS referrals_out_of_network,
  COALESCE(img.imaging_orders, 0)              AS imaging_orders
FROM spine s
LEFT JOIN `veridian_health.facilities` f ON s.facility_id = f.facility_id
LEFT JOIN enc  ON s.month = enc.month  AND s.facility_id = enc.facility_id
LEFT JOIN bed  ON s.month = bed.month  AND s.facility_id = bed.facility_id
LEFT JOIN appt ON s.month = appt.month AND s.facility_id = appt.facility_id
LEFT JOIN pa   ON s.month = pa.month   AND s.facility_id = pa.facility_id
LEFT JOIN ref  ON s.month = ref.month  AND s.facility_id = ref.facility_id
LEFT JOIN img  ON s.month = img.month  AND s.facility_id = img.facility_id;

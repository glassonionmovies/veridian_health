-- ============================================================================
--  fact_it_servicedesk_month
--  Grain : month × facility
--  Source: service_desk_tickets, it_change_requests
--  Powers: IT service-desk health (FCR / self-service / reopen) and change
--          management (success / emergency / change-caused incidents / lead time)
-- ----------------------------------------------------------------------------
--  TWO sources of different event grain rolled to the common month × facility
--  key. DESK month = DATE_TRUNC(opened_at). CHANGE month = DATE_TRUNC(
--  implemented_at) when implemented, else scheduled_at (so not-yet-implemented
--  changes still land in their scheduled month). category/channel become
--  COUNTIF measures — they are NOT part of the grain.
--  first_contact_count is an FCR proxy = resolved AND NOT reopened (the raw
--  has no true first-contact flag; documented here per convention).
--  change_lead_time_minutes_sum is additive (SUM of per-change minutes); the
--  AVG lead time is computed at read = lead_time_sum / change_total.
--  Built from a (month, facility) spine UNION'd across both sources so a
--  facility present in only one source still gets a row; measures COALESCE to 0.
--  NOTE: it_change_requests is NOT facility-attributed (facility_id is NULL —
--  changes are enterprise/system-scoped), so change measures roll up onto
--  facility_id = NULL rows. The join is NULL-safe so those rows populate; the
--  exec scorecard sums by month, so change/DORA KPIs aggregate correctly.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_it_servicedesk_month`
PARTITION BY month
CLUSTER BY facility_id
AS
WITH desk AS (
  SELECT
    DATE_TRUNC(DATE(opened_at), MONTH)                                AS month,
    facility_id,
    COUNT(*)                                                          AS ticket_count,
    COUNTIF(resolved_at IS NOT NULL)                                  AS resolved_count,
    SUM(IF(resolution_minutes IS NOT NULL,
           resolution_minutes, CAST(0 AS NUMERIC)))                  AS resolution_minutes_sum,
    COUNTIF(is_self_service)                                          AS self_service_count,
    -- FCR proxy: resolved and never reopened (raw lacks a true first-contact flag)
    COUNTIF(NOT reopened AND resolved_at IS NOT NULL)                 AS first_contact_count,
    COUNTIF(reopened)                                                 AS reopened_count,
    COUNTIF(channel = 'PHONE')                                        AS phone_count,
    COUNTIF(channel = 'PORTAL')                                       AS portal_count,
    COUNTIF(channel = 'SELF_SERVICE')                                 AS selfservice_count,
    COUNTIF(channel = 'WALKUP')                                       AS walkup_count
  FROM `veridian_health.service_desk_tickets`
  GROUP BY month, facility_id
),
chg AS (
  SELECT
    DATE_TRUNC(DATE(COALESCE(implemented_at, scheduled_at)), MONTH)   AS month,
    facility_id,
    COUNT(*)                                                          AS change_total,
    COUNTIF(status = 'SUCCESS')                                       AS change_success_count,
    COUNTIF(status != 'SUCCESS')                                      AS change_failed_count,
    COUNTIF(caused_incident)                                          AS change_caused_incident_count,
    COUNTIF(change_type = 'EMERGENCY')                                AS change_emergency_count,
    SUM(IF(implemented_at IS NOT NULL AND scheduled_at IS NOT NULL,
           TIMESTAMP_DIFF(implemented_at, scheduled_at, MINUTE),
           0))                                                        AS change_lead_time_minutes_sum
  FROM `veridian_health.it_change_requests`
  GROUP BY month, facility_id
),
spine AS (
  SELECT month, facility_id FROM desk
  UNION DISTINCT
  SELECT month, facility_id FROM chg
)
SELECT
  s.month,
  s.facility_id,
  f.facility_name,
  f.region,
  -- DESK measures
  COALESCE(desk.ticket_count, 0)                          AS ticket_count,
  COALESCE(desk.resolved_count, 0)                        AS resolved_count,
  COALESCE(desk.resolution_minutes_sum, CAST(0 AS NUMERIC)) AS resolution_minutes_sum,
  COALESCE(desk.self_service_count, 0)                    AS self_service_count,
  COALESCE(desk.first_contact_count, 0)                   AS first_contact_count,
  COALESCE(desk.reopened_count, 0)                        AS reopened_count,
  COALESCE(desk.phone_count, 0)                           AS phone_count,
  COALESCE(desk.portal_count, 0)                          AS portal_count,
  COALESCE(desk.selfservice_count, 0)                     AS selfservice_count,
  COALESCE(desk.walkup_count, 0)                          AS walkup_count,
  -- CHANGE measures
  COALESCE(chg.change_total, 0)                           AS change_total,
  COALESCE(chg.change_success_count, 0)                   AS change_success_count,
  COALESCE(chg.change_failed_count, 0)                    AS change_failed_count,
  COALESCE(chg.change_caused_incident_count, 0)           AS change_caused_incident_count,
  COALESCE(chg.change_emergency_count, 0)                 AS change_emergency_count,
  COALESCE(chg.change_lead_time_minutes_sum, 0)          AS change_lead_time_minutes_sum
FROM spine s
LEFT JOIN `veridian_health.facilities` f ON s.facility_id = f.facility_id
-- NULL-safe join: changes are facility-less (facility_id NULL) and must still land.
LEFT JOIN desk ON s.month = desk.month AND COALESCE(s.facility_id,'~ENT~') = COALESCE(desk.facility_id,'~ENT~')
LEFT JOIN chg  ON s.month = chg.month  AND COALESCE(s.facility_id,'~ENT~') = COALESCE(chg.facility_id,'~ENT~');

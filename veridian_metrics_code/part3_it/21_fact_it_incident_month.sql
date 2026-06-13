-- =====================================================================
--  fact_it_incident_month   (IT incident facts rolled to month×facility×system)
--  Grain : month × facility_id × system_id  (facility_id may be NULL for enterprise-wide)
--  Source: veridian_health.it_incidents
--  Powers: IT reliability / clinical-downtime KPIs, SEV mix, change-caused
--           failures, MTTR inputs, incident SLA attainment (IT ops discipline)
-- ---------------------------------------------------------------------
--  Additive measures only; ratios (MTTR, %within-SLA, %clinical) computed at read.
--  No month spine — only emit (month,facility,system) tuples that have incidents.
--  within_sla_count uses severity→target SLA (min): SEV1 240, SEV2 480,
--  SEV3 1440, SEV4 4320; resolution_minutes_sum counts resolved rows only.
-- =====================================================================
CREATE OR REPLACE TABLE `veridian_metrics.fact_it_incident_month`
PARTITION BY month
CLUSTER BY facility_id AS
WITH inc AS (
  SELECT
    DATE_TRUNC(DATE(opened_at), MONTH) AS month,
    facility_id,
    system_id,
    severity,
    duration_minutes,
    resolved_at,
    is_clinical_downtime,
    root_cause
  FROM `veridian_health.it_incidents`
)
SELECT
  month,
  facility_id,
  system_id,
  COUNT(*)                                                          AS incident_count,
  COUNTIF(severity = 'SEV1')                                        AS sev1_count,
  COUNTIF(severity = 'SEV2')                                        AS sev2_count,
  COUNTIF(severity = 'SEV3')                                        AS sev3_count,
  COUNTIF(severity = 'SEV4')                                        AS sev4_count,
  COUNTIF(resolved_at IS NOT NULL)                                  AS resolved_count,
  SUM(IF(resolved_at IS NOT NULL, duration_minutes, CAST(0 AS NUMERIC)))
                                                                    AS resolution_minutes_sum,
  COALESCE(SUM(duration_minutes), CAST(0 AS NUMERIC))               AS downtime_minutes_sum,
  SUM(IF(is_clinical_downtime, duration_minutes, CAST(0 AS NUMERIC)))
                                                                    AS clinical_downtime_minutes,
  COUNTIF(is_clinical_downtime)                                     AS clinical_downtime_count,
  COUNTIF(root_cause = 'CHANGE')                                    AS change_caused_count,
  COUNTIF(
    duration_minutes <= CASE severity
                          WHEN 'SEV1' THEN 240
                          WHEN 'SEV2' THEN 480
                          WHEN 'SEV3' THEN 1440
                          WHEN 'SEV4' THEN 4320
                        END
  )                                                                 AS within_sla_count
FROM inc
GROUP BY month, facility_id, system_id;

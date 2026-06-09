-- ============================================================================
--  fact_quality_month
--  Grain : month × facility
--  Source: quality_safety_events, cdi_queries, charges, claims,
--          care_management  (facility via encounters where needed)
--  Powers: metrics 10,41–50 ; feeds exec_kpi_month
-- ----------------------------------------------------------------------------
--  Snapshot-style integrity signals (credentialing lapse, EMPI dup pairs) live
--  in the worklists (14,15) — this monthly fact carries the TRENDABLE measures.
--  Facility attribution for encounter-grain sources (cdi, charges, claims,
--  care_management) is via encounters.facility_id.
--  Built from a (month, facility) spine; per-source measures COALESCE to 0.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_quality_month`
PARTITION BY month
CLUSTER BY facility_id
AS
WITH qse AS (
  SELECT
    DATE_TRUNC(DATE(event_datetime), MONTH)                   AS month,
    facility_id,
    COUNT(*)                                                  AS safety_events,
    COUNTIF(severity IN ('SEVERE','DEATH'))                  AS serious_safety_events,
    COUNTIF(event_type = 'READMISSION_30D')                  AS readmissions_30d,
    COUNTIF(is_preventable)                                  AS preventable_events
  FROM `veridian_health.quality_safety_events`
  GROUP BY month, facility_id
),
cdi AS (
  SELECT
    DATE_TRUNC(DATE(q.created_datetime), MONTH)               AS month,
    e.facility_id,
    COUNT(*)                                                  AS cdi_queries,
    COUNTIF(q.query_status IN ('ANSWERED','AGREED','DISAGREED')) AS cdi_responses,
    COUNTIF(q.query_status = 'NO_RESPONSE')                  AS cdi_no_response,
    SUM(IF(q.financial_impact IS NOT NULL, q.financial_impact, CAST(0 AS NUMERIC))) AS cdi_financial_impact
  FROM `veridian_health.cdi_queries` q
  JOIN `veridian_health.encounters` e ON q.encounter_id = e.encounter_id
  GROUP BY month, e.facility_id
),
dupchg AS (
  -- duplicate POSTED charges: same encounter+cpt+amount posted more than once
  SELECT
    DATE_TRUNC(DATE(charge_datetime), MONTH)                  AS month,
    facility_id,
    COUNT(*)                                                  AS duplicate_charge_lines
  FROM (
    SELECT
      ch.encounter_id, e.facility_id, ch.charge_datetime, ch.cpt_code,
      COUNT(*) OVER (PARTITION BY ch.encounter_id, ch.cpt_code, ch.billed_amount) AS dup_n
    FROM `veridian_health.charges` ch
    JOIN `veridian_health.encounters` e ON ch.encounter_id = e.encounter_id
    WHERE ch.status = 'POSTED'
  )
  WHERE dup_n > 1
  GROUP BY month, facility_id
),
clm AS (
  SELECT
    DATE_TRUNC(DATE(c.submission_datetime), MONTH)            AS month,
    e.facility_id,
    COUNTIF(c.denial_code = 'CO-197')                        AS co197_denials
  FROM `veridian_health.claims` c
  JOIN `veridian_health.encounters` e ON c.encounter_id = e.encounter_id
  GROUP BY month, e.facility_id
),
cm AS (
  SELECT
    DATE_TRUNC(DATE(t.created_datetime), MONTH)               AS month,
    e.facility_id,
    COUNTIF(t.task_type = 'SNF_PLACEMENT_REQUEST')          AS snf_requests,
    COUNTIF(t.task_type = 'SNF_PLACEMENT_REQUEST'
            AND t.task_status = 'NOT_STARTED')              AS snf_requests_not_started
  FROM `veridian_health.care_management` t
  JOIN `veridian_health.encounters` e ON t.encounter_id = e.encounter_id
  GROUP BY month, e.facility_id
),
spine AS (
  SELECT month, facility_id FROM qse
  UNION DISTINCT SELECT month, facility_id FROM cdi
  UNION DISTINCT SELECT month, facility_id FROM dupchg
  UNION DISTINCT SELECT month, facility_id FROM clm
  UNION DISTINCT SELECT month, facility_id FROM cm
)
SELECT
  s.month,
  s.facility_id,
  f.facility_name,
  f.region,
  COALESCE(qse.safety_events, 0)                AS safety_events,
  COALESCE(qse.serious_safety_events, 0)        AS serious_safety_events,
  COALESCE(qse.readmissions_30d, 0)             AS readmissions_30d,
  COALESCE(qse.preventable_events, 0)           AS preventable_events,
  COALESCE(cdi.cdi_queries, 0)                  AS cdi_queries,
  COALESCE(cdi.cdi_responses, 0)                AS cdi_responses,
  COALESCE(cdi.cdi_no_response, 0)              AS cdi_no_response,
  COALESCE(cdi.cdi_financial_impact, CAST(0 AS NUMERIC)) AS cdi_financial_impact,
  COALESCE(dupchg.duplicate_charge_lines, 0)    AS duplicate_charge_lines,
  COALESCE(clm.co197_denials, 0)                AS co197_denials,
  COALESCE(cm.snf_requests, 0)                  AS snf_requests,
  COALESCE(cm.snf_requests_not_started, 0)      AS snf_requests_not_started
FROM spine s
LEFT JOIN `veridian_health.facilities` f ON s.facility_id = f.facility_id
LEFT JOIN qse    ON s.month = qse.month    AND s.facility_id = qse.facility_id
LEFT JOIN cdi    ON s.month = cdi.month    AND s.facility_id = cdi.facility_id
LEFT JOIN dupchg ON s.month = dupchg.month AND s.facility_id = dupchg.facility_id
LEFT JOIN clm    ON s.month = clm.month    AND s.facility_id = clm.facility_id
LEFT JOIN cm     ON s.month = cm.month     AND s.facility_id = cm.facility_id;

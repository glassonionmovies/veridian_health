-- ============================================================================
--  fact_it_dex_month
--  Grain : period × facility × department   (digital clinician experience)
--  Source: clinician_ehr_usage, ai_tool_usage
--  Powers: clinician burnout / EHR-burden + AI-adoption KPIs (IT DEX discipline)
-- ----------------------------------------------------------------------------
--  Both sources are already month-grain (period is a DATE month); we DATE_TRUNC
--  to MONTH defensively and roll each to (period, facility, department).
--  system_id is DROPPED from the grain: ai_tool_usage carries no system_id, so a
--  system-level grain isn't derivable across both sources — facility×department
--  is the common conformed key. Mean login latency = login_seconds_sum /
--  login_observations and governed-share = governed_session_count / ai_sessions_sum
--  are computed at READ time (ratios are never stored). Built from a UNION-DISTINCT
--  key spine so a (period,fac,dept) present in one source still gets a row;
--  per-source measures COALESCE to 0.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_it_dex_month`
PARTITION BY period
CLUSTER BY facility_id
AS
WITH dex AS (
  SELECT
    DATE_TRUNC(period, MONTH)                                AS period,
    facility_id,
    department_id,
    SUM(total_ehr_minutes)                                   AS total_ehr_minutes_sum,
    SUM(after_hours_minutes)                                 AS after_hours_minutes_sum,
    SUM(inbasket_messages)                                   AS inbasket_messages_sum,
    SUM(avg_login_seconds)                                   AS login_seconds_sum,
    COUNT(*)                                                 AS login_observations,
    COUNT(DISTINCT provider_npi)                             AS active_providers
  FROM `veridian_health.clinician_ehr_usage`
  GROUP BY period, facility_id, department_id
),
ai AS (
  SELECT
    DATE_TRUNC(period, MONTH)                                AS period,
    facility_id,
    department_id,
    SUM(sessions)                                            AS ai_sessions_sum,
    SUM(minutes_saved)                                       AS ai_minutes_saved_sum,
    SUM(IF(is_governed, sessions, 0))                        AS governed_session_count,
    COUNT(DISTINCT provider_npi)                             AS adopting_provider_count
  FROM `veridian_health.ai_tool_usage`
  GROUP BY period, facility_id, department_id
),
spine AS (
  SELECT period, facility_id, department_id FROM dex
  UNION DISTINCT
  SELECT period, facility_id, department_id FROM ai
)
SELECT
  s.period,
  s.facility_id,
  s.department_id,
  COALESCE(dex.total_ehr_minutes_sum, 0)        AS total_ehr_minutes_sum,
  COALESCE(dex.after_hours_minutes_sum, 0)      AS after_hours_minutes_sum,
  COALESCE(dex.inbasket_messages_sum, 0)        AS inbasket_messages_sum,
  COALESCE(dex.login_seconds_sum, 0)            AS login_seconds_sum,
  COALESCE(dex.login_observations, 0)           AS login_observations,
  COALESCE(dex.active_providers, 0)             AS active_providers,
  COALESCE(ai.ai_sessions_sum, 0)               AS ai_sessions_sum,
  COALESCE(ai.ai_minutes_saved_sum, 0)          AS ai_minutes_saved_sum,
  COALESCE(ai.governed_session_count, 0)        AS governed_session_count,
  COALESCE(ai.adopting_provider_count, 0)       AS adopting_provider_count
FROM spine s
LEFT JOIN dex ON s.period = dex.period
            AND s.facility_id = dex.facility_id
            AND s.department_id = dex.department_id
LEFT JOIN ai  ON s.period = ai.period
            AND s.facility_id = ai.facility_id
            AND s.department_id = ai.department_id;

-- ============================================================================
--  fact_it_security_month
--  Grain : month × facility × severity   (accumulating snapshot)
--  Source: it_vulnerabilities, facilities
--  Powers: CIO security-exposure KPIs (open CRITICAL/HIGH backlog, SLA
--          attainment, remediation MTTR, ransomware-exposure heatmap)
-- ----------------------------------------------------------------------------
--  ACCUMULATING SNAPSHOT: a full month spine (GENERATE_DATE_ARRAY 2023-06..
--  2026-05) is CROSS-joined to every (facility, severity) combo seen in the raw
--  findings, so the open-backlog measures (open_findings_eom, exposure_age) are
--  recomputed as-of each month-end (LAST_DAY) even for months with no events.
--  facility_id / severity come straight off it_vulnerabilities (facility_id is
--  denormalized there — it_assets is NOT needed for attribution). Open set at
--  month_end = detected_date <= month_end AND (patched_date IS NULL OR
--  patched_date > month_end). SLA bands recomputed for patched-in-month rows
--  (CRITICAL 7d / HIGH 30d / MEDIUM 90d); LOW has no SLA target so it falls back
--  to the raw sla_breached flag. FACTS carry ADDITIVE measures only (counts +
--  day-sums); rates (SLA %, mean remediation days) are computed at READ time.
--  Measures COALESCE to 0 (NUMERIC -> CAST(0 AS NUMERIC)).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.fact_it_security_month`
PARTITION BY month
CLUSTER BY facility_id
AS
WITH params AS (
  SELECT DATE '2026-06-04' AS as_of
),
months AS (
  SELECT m AS month, LAST_DAY(m) AS month_end
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE '2023-06-01', DATE '2026-05-01',
                                  INTERVAL 1 MONTH)) AS m
),
-- (facility, severity) universe observed in the raw findings — no hardcoded
-- domain values (severity bands & facilities come from the data at runtime).
combos AS (
  SELECT DISTINCT facility_id, severity
  FROM `veridian_health.it_vulnerabilities`
  WHERE facility_id IS NOT NULL AND severity IS NOT NULL
),
spine AS (
  SELECT mo.month, mo.month_end, c.facility_id, c.severity
  FROM months mo
  CROSS JOIN combos c
),
-- per-month flow measures: new, remediated, and remediation/SLA on rows
-- patched WITHIN the month.
flow AS (
  SELECT
    DATE_TRUNC(v.detected_date, MONTH)                          AS det_month,
    DATE_TRUNC(v.patched_date,  MONTH)                          AS pat_month,
    v.facility_id,
    v.severity,
    v.detected_date,
    v.patched_date,
    v.sla_breached
  FROM `veridian_health.it_vulnerabilities` v
  WHERE v.facility_id IS NOT NULL AND v.severity IS NOT NULL
),
newf AS (
  SELECT det_month AS month, facility_id, severity,
         COUNT(*) AS new_findings
  FROM flow
  GROUP BY month, facility_id, severity
),
remf AS (
  SELECT
    pat_month AS month,
    facility_id,
    severity,
    COUNT(*)                                                    AS remediated_findings,
    COUNT(*)                                                    AS remediated_count,
    SUM(DATE_DIFF(patched_date, detected_date, DAY))           AS remediation_days_sum,
    -- recompute SLA vs band for the three SLA-bearing severities; LOW (no
    -- target) falls back to the raw sla_breached flag.
    COUNTIF(
      CASE severity
        WHEN 'CRITICAL' THEN DATE_DIFF(patched_date, detected_date, DAY) <= 7
        WHEN 'HIGH'     THEN DATE_DIFF(patched_date, detected_date, DAY) <= 30
        WHEN 'MEDIUM'   THEN DATE_DIFF(patched_date, detected_date, DAY) <= 90
        ELSE NOT COALESCE(sla_breached, FALSE)
      END
    )                                                           AS within_sla_count,
    COUNTIF(
      CASE severity
        WHEN 'CRITICAL' THEN DATE_DIFF(patched_date, detected_date, DAY) > 7
        WHEN 'HIGH'     THEN DATE_DIFF(patched_date, detected_date, DAY) > 30
        WHEN 'MEDIUM'   THEN DATE_DIFF(patched_date, detected_date, DAY) > 90
        ELSE COALESCE(sla_breached, FALSE)
      END
    )                                                           AS sla_breached_count
  FROM flow
  WHERE patched_date IS NOT NULL
  GROUP BY month, facility_id, severity
),
-- open backlog as-of each month_end (accumulating): join the full finding set
-- to the spine on facility+severity, keep rows open at that month_end.
openf AS (
  SELECT
    s.month,
    s.facility_id,
    s.severity,
    COUNT(*)                                                    AS open_findings_eom,
    COUNTIF(s.severity = 'CRITICAL')                            AS open_critical_eom,
    COUNTIF(s.severity = 'HIGH')                                AS open_high_eom,
    SUM(DATE_DIFF(s.month_end, v.detected_date, DAY))           AS exposure_age_days_sum
  FROM spine s
  JOIN `veridian_health.it_vulnerabilities` v
    ON v.facility_id = s.facility_id
   AND v.severity    = s.severity
   AND v.detected_date <= s.month_end
   AND (v.patched_date IS NULL OR v.patched_date > s.month_end)
  GROUP BY s.month, s.facility_id, s.severity
)
SELECT
  s.month,
  s.facility_id,
  f.facility_name,
  f.region,
  s.severity,
  COALESCE(newf.new_findings, 0)                 AS new_findings,
  COALESCE(remf.remediated_findings, 0)          AS remediated_findings,
  COALESCE(remf.remediated_count, 0)             AS remediated_count,
  COALESCE(remf.remediation_days_sum, 0)         AS remediation_days_sum,
  COALESCE(remf.within_sla_count, 0)             AS within_sla_count,
  COALESCE(remf.sla_breached_count, 0)           AS sla_breached_count,
  COALESCE(openf.open_findings_eom, 0)           AS open_findings_eom,
  COALESCE(openf.open_critical_eom, 0)           AS open_critical_eom,
  COALESCE(openf.open_high_eom, 0)               AS open_high_eom,
  COALESCE(openf.exposure_age_days_sum, 0)       AS exposure_age_days_sum
FROM spine s
LEFT JOIN `veridian_health.facilities` f ON s.facility_id = f.facility_id
LEFT JOIN newf  ON s.month = newf.month  AND s.facility_id = newf.facility_id  AND s.severity = newf.severity
LEFT JOIN remf  ON s.month = remf.month  AND s.facility_id = remf.facility_id  AND s.severity = remf.severity
LEFT JOIN openf ON s.month = openf.month AND s.facility_id = openf.facility_id AND s.severity = openf.severity;

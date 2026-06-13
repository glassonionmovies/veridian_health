-- ============================================================================
--  worklist_open_critical_vulns   (one row per open CRITICAL/HIGH finding)
--  Grain : one OPEN (unpatched) critical/high finding, past or in SLA window
--  Source: it_vulnerabilities, it_assets, it_systems, facilities
--  Powers: security-remediation worklist (open critical/high vuln exposure;
--          clinical-system & legacy-facility prioritization)
-- ----------------------------------------------------------------------------
--  Open = patched_date IS NULL. SLA window: CRITICAL detected+7d, HIGH +30d.
--  is_sla_breached trusts the raw sla_breached flag OR recomputes as_of>due.
--  exposure_score is deterministic (severity weight {CRITICAL 10, HIGH 5} ×
--  days_open) — additive-only intent; ranking happens at read, no ORDER BY.
--  Asset-level finding: keys come straight off the finding (no roll-up).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_open_critical_vulns`
CLUSTER BY facility_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of)
SELECT
  v.finding_id,
  v.cve,
  v.severity,
  v.asset_id,
  v.system_id,
  s.system_name,
  v.facility_id,
  f.region,
  f.is_legacy,
  v.days_open,
  DATE_ADD(v.detected_date,
           INTERVAL IF(v.severity = 'CRITICAL', 7, 30) DAY)                       AS sla_due_date,
  COALESCE(v.sla_breached, FALSE)
    OR p.as_of > DATE_ADD(v.detected_date,
                          INTERVAL IF(v.severity = 'CRITICAL', 7, 30) DAY)        AS is_sla_breached,
  COALESCE(s.criticality LIKE 'TIER1%', FALSE)                                    AS is_clinical_system,
  CASE v.severity WHEN 'CRITICAL' THEN 10 WHEN 'HIGH' THEN 5 ELSE 0 END
    * COALESCE(v.days_open, 0)                                                    AS exposure_score
FROM `veridian_health.it_vulnerabilities` v
CROSS JOIN params p
LEFT JOIN `veridian_health.it_assets`  a ON v.asset_id  = a.asset_id
LEFT JOIN `veridian_health.it_systems` s ON v.system_id = s.system_id
LEFT JOIN `veridian_health.facilities` f ON v.facility_id = f.facility_id
WHERE v.patched_date IS NULL
  AND v.severity IN ('CRITICAL', 'HIGH')
  -- keep rows that are SLA-breached OR still inside the active SLA window
  AND (
        COALESCE(v.sla_breached, FALSE)
        OR p.as_of >  DATE_ADD(v.detected_date, INTERVAL IF(v.severity = 'CRITICAL', 7, 30) DAY)
        OR p.as_of <= DATE_ADD(v.detected_date, INTERVAL IF(v.severity = 'CRITICAL', 7, 30) DAY)
      );
-- (No ORDER BY: ranked at read time by the metric detail_sql; BQ forbids ORDER BY + CLUSTER BY in CTAS.)

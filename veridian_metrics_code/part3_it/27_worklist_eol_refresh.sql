-- ============================================================================
--  worklist_eol_refresh   (one row per EOL/unsupported/patch-stale asset or past-EOL system)
--  Grain : one row per asset (item_kind='ASSET') or system (item_kind='SYSTEM')
--  Source: it_assets, it_systems, it_vulnerabilities, facilities
--  Powers: lifecycle / technical-debt refresh planning (TIME-Eliminate),
--          end-of-life exposure, patch-hygiene remediation
-- ----------------------------------------------------------------------------
--  Two source grains UNION ALL'd into a conformed worklist row:
--    (a) ASSET  — it_assets where is_end_of_life OR days_since_patch > 90.
--                 days_past_eol carries days_since_patch (the asset staleness clock);
--                 open_critical_findings = open CRITICAL vulns on that asset
--                 (open = patched_date IS NULL); annual_run_cost is NULL (assets
--                 have no run-cost line — noted, not invented).
--    (b) SYSTEM — it_systems where end_of_life_date <= as_of (past EOL, TIME-Eliminate).
--                 days_past_eol = days since the system's EOL date; open_critical_findings
--                 forced to 0 (findings are asset-grain only); annual_run_cost = annual_cost.
--  hosts_clinical_system = the owning/affiliated system is TIER1_LIFE_SAFETY.
--  refresh_priority_score is a deterministic ADDITIVE score (EOL state, clinical
--  blast radius, legacy facility, open critical findings, staleness/run cost);
--  ranking happens at READ time. No ratios stored. No ORDER BY (CLUSTER BY CTAS).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_eol_refresh`
CLUSTER BY facility_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
-- Open CRITICAL findings per asset (open = not yet patched).
crit AS (
  SELECT
    asset_id,
    COUNTIF(severity = 'CRITICAL' AND patched_date IS NULL) AS open_critical_findings
  FROM `veridian_health.it_vulnerabilities`
  WHERE asset_id IS NOT NULL
  GROUP BY asset_id
),
-- (a) ASSET branch: end-of-life OR patch-stale (>90 days since last patch).
assets AS (
  SELECT
    'ASSET'                                                     AS item_kind,
    a.asset_id                                                  AS item_id,
    a.asset_type                                                AS label,
    a.facility_id,
    f.region,
    f.is_legacy,
    -- staleness clock = days since last patch (NULL-safe)
    DATE_DIFF(p.as_of, a.last_patched_date, DAY)                AS days_past_eol,
    COALESCE(c.open_critical_findings, 0)                       AS open_critical_findings,
    CAST(NULL AS NUMERIC)                                       AS annual_run_cost,
    COALESCE(s.criticality = 'TIER1_LIFE_SAFETY', FALSE)        AS hosts_clinical_system,
    a.is_end_of_life                                            AS is_eol_flag,
    COALESCE(DATE_DIFF(p.as_of, a.last_patched_date, DAY), 0)   AS staleness_days
  FROM `veridian_health.it_assets` a
  CROSS JOIN params p
  LEFT JOIN `veridian_health.facilities` f ON a.facility_id = f.facility_id
  LEFT JOIN `veridian_health.it_systems` s ON a.system_id   = s.system_id
  LEFT JOIN crit c                          ON a.asset_id    = c.asset_id
  WHERE a.is_end_of_life
     OR DATE_DIFF(p.as_of, a.last_patched_date, DAY) > 90
),
-- (b) SYSTEM branch: past end-of-life as of the anchor (TIME-Eliminate).
systems AS (
  SELECT
    'SYSTEM'                                                    AS item_kind,
    s.system_id                                                 AS item_id,
    s.capability                                                AS label,
    s.owning_facility_id                                        AS facility_id,
    f.region,
    f.is_legacy,
    DATE_DIFF(p.as_of, s.end_of_life_date, DAY)                 AS days_past_eol,
    0                                                           AS open_critical_findings,
    s.annual_cost                                               AS annual_run_cost,
    s.criticality = 'TIER1_LIFE_SAFETY'                         AS hosts_clinical_system,
    TRUE                                                        AS is_eol_flag,
    0                                                           AS staleness_days
  FROM `veridian_health.it_systems` s
  CROSS JOIN params p
  LEFT JOIN `veridian_health.facilities` f ON s.owning_facility_id = f.facility_id
  WHERE s.end_of_life_date IS NOT NULL
    AND s.end_of_life_date <= p.as_of
),
unioned AS (
  SELECT * FROM assets
  UNION ALL
  SELECT * FROM systems
)
SELECT
  u.item_kind,
  u.item_id,
  u.label,
  u.facility_id,
  u.region,
  u.is_legacy,
  u.days_past_eol,
  u.open_critical_findings,
  u.annual_run_cost,
  u.hosts_clinical_system,
  -- Deterministic additive refresh-priority score (higher = remediate sooner).
  ( IF(u.is_eol_flag, 40, 0)
  + IF(u.hosts_clinical_system, 30, 0)
  + IF(COALESCE(u.is_legacy, FALSE), 15, 0)
  + LEAST(u.open_critical_findings, 5) * 5
  + IF(u.staleness_days > 180, 10, IF(u.staleness_days > 90, 5, 0))
  + IF(COALESCE(u.annual_run_cost, CAST(0 AS NUMERIC)) > 1000000, 10, 0) ) AS refresh_priority_score
FROM unioned u;
-- (No ORDER BY: ranked at read time; BigQuery forbids ORDER BY + CLUSTER BY in CTAS.)

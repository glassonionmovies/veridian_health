-- ============================================================================
--  dim_it_asset   (current-snapshot dimension; one row per IT asset)
--  Grain : one row per asset, as_of snapshot
--  Source: it_assets, facilities (region/is_legacy), it_vulnerabilities (open findings/asset)
--  Powers: IT asset-hygiene / refresh-risk worklists; patch-currency & EOL exposure
-- ----------------------------------------------------------------------------
--  patch_currency_band buckets days_since_patch (CURRENT<=30 / <=90 / STALE>90 /
--  NULL=NEVER). open_findings/open_critical_findings count it_vulnerabilities with
--  patched_date IS NULL for the asset. EOL flag = it_assets.is_end_of_life (no
--  separate supported-OS source). refresh_due = is_end_of_life OR days_since_patch>90.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.dim_it_asset`
CLUSTER BY facility_id
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
vuln AS (
  SELECT
    asset_id,
    COUNT(*)                                AS open_findings,
    COUNTIF(severity = 'CRITICAL')          AS open_critical_findings
  FROM `veridian_health.it_vulnerabilities`
  WHERE patched_date IS NULL
  GROUP BY asset_id
),
base AS (
  SELECT
    a.asset_id,
    a.asset_type,
    a.facility_id,
    f.region,
    f.is_legacy,
    a.department_id,
    a.system_id,
    a.vendor_id,
    a.os_family,
    a.os_version,
    a.is_end_of_life,
    a.last_patched_date,
    DATE_DIFF(p.as_of, a.last_patched_date, DAY) AS days_since_patch
  FROM `veridian_health.it_assets` a
  CROSS JOIN params p
  LEFT JOIN `veridian_health.facilities` f USING (facility_id)
)
SELECT
  b.asset_id,
  b.asset_type,
  b.facility_id,
  b.region,
  b.is_legacy,
  b.department_id,
  b.system_id,
  b.vendor_id,
  b.os_family,
  b.os_version,
  b.is_end_of_life,
  b.last_patched_date,
  b.days_since_patch,
  CASE
    WHEN b.last_patched_date IS NULL    THEN 'NEVER'
    WHEN b.days_since_patch <= 30       THEN 'CURRENT'
    WHEN b.days_since_patch <= 90       THEN 'AGING'
    ELSE 'STALE'
  END AS patch_currency_band,
  COALESCE(v.open_findings, 0)          AS open_findings,
  COALESCE(v.open_critical_findings, 0) AS open_critical_findings,
  (b.is_end_of_life OR b.days_since_patch > 90) AS refresh_due
FROM base b
LEFT JOIN vuln v ON b.asset_id = v.asset_id;

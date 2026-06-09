-- ============================================================================
--  dim_provider   (current-snapshot dimension; current SCD-2 version only)
--  Source: providers (is_current), claims, encounters (TTM)
--  Powers: metrics 44 (credentialing), 47 (documentation quality)
-- ----------------------------------------------------------------------------
--  Provider→activity attribution is via encounters.attending_provider_npi
--  (claims have no provider column). TTM = trailing 12 months from as_of.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.dim_provider`
CLUSTER BY primary_facility_id, credentialing_status
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
enc AS (
  SELECT
    e.attending_provider_npi AS provider_npi,
    COUNT(*) AS encounters_ttm
  FROM `veridian_health.encounters` e, params p
  WHERE e.attending_provider_npi IS NOT NULL
    AND DATE(e.admission_datetime) > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY provider_npi
),
clm AS (
  SELECT
    e.attending_provider_npi AS provider_npi,
    COUNT(*)                  AS claims_ttm,
    SUM(c.total_billed_amount) AS billed_ttm
  FROM `veridian_health.claims` c
  JOIN `veridian_health.encounters` e ON c.encounter_id = e.encounter_id, params p
  WHERE e.attending_provider_npi IS NOT NULL
    AND DATE(c.submission_datetime) > DATE_SUB(p.as_of, INTERVAL 12 MONTH)
  GROUP BY provider_npi
)
SELECT
  pr.provider_sk,
  pr.provider_npi,
  pr.provider_name_hash,
  pr.specialty,
  pr.department_id,
  pr.primary_facility_id,
  pr.credentialing_status,
  pr.documentation_quality_flag,
  COALESCE(enc.encounters_ttm, 0) AS encounters_ttm,
  COALESCE(clm.claims_ttm, 0)     AS claims_ttm,
  clm.billed_ttm
FROM `veridian_health.providers` pr
LEFT JOIN enc ON pr.provider_npi = enc.provider_npi
LEFT JOIN clm ON pr.provider_npi = clm.provider_npi
WHERE pr.is_current;

-- ============================================================================
--  worklist_credentialing_exposure   (one row per lapsed-credential provider)
--  Source: providers, encounters, claims
--  Powers: metric 44 (planted: 31 claims billed under a lapsed-credential provider)
-- ----------------------------------------------------------------------------
--  Claim→provider attribution via encounters.attending_provider_npi.
--  Matches validate.sql credentialing_lapse_31 EXACTLY: join providers on
--  provider_npi (NOT is_current) and filter credentialing_status = 'LAPSED'
--  only (TERMINATED is a different, much larger population and is excluded).
--  Grouped to one row per provider; SUM(lapse_claims) reproduces the planted 31.
--  dollars_at_risk = billed on those claims (recoupment / compliance exposure).
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_credentialing_exposure`
AS
SELECT
  pr.provider_npi,
  ANY_VALUE(pr.provider_name_hash)   AS provider_name_hash,
  ANY_VALUE(pr.specialty)            AS specialty,
  ANY_VALUE(pr.primary_facility_id)  AS primary_facility_id,
  ANY_VALUE(pr.credentialing_status) AS credentialing_status,
  COUNT(c.claim_id)                  AS lapse_claims,
  SUM(c.total_billed_amount)         AS dollars_at_risk
FROM `veridian_health.claims` c
JOIN `veridian_health.encounters` e ON c.encounter_id = e.encounter_id
JOIN `veridian_health.providers` pr ON e.attending_provider_npi = pr.provider_npi
WHERE pr.credentialing_status = 'LAPSED'
GROUP BY pr.provider_npi;

-- ============================================================================
--  worklist_empi_duplicate_pairs   (one row per candidate duplicate patient pair)
--  Source: patient_master_index
--  Powers: metric 46 (planted: 40 cross-EHR duplicate patient pairs <0.85 conf)
-- ----------------------------------------------------------------------------
--  Candidate pair = two DIFFERENT master_patient_ids sharing a name_hash where
--  at least one side has match_confidence_score < 0.85. id_a < id_b dedupes the
--  symmetric pair. Reconcile against validate.sql (empi_duplicate_pairs_40);
--  if the planted pairs use merge_history rather than name_hash collisions,
--  swap the join key accordingly.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_empi_duplicate_pairs`
AS
SELECT
  a.master_patient_id      AS master_patient_id_a,
  b.master_patient_id      AS master_patient_id_b,
  a.name_hash,
  a.match_confidence_score AS confidence_a,
  b.match_confidence_score AS confidence_b,
  a.primary_facility_id    AS facility_a,
  b.primary_facility_id    AS facility_b,
  LEAST(a.match_confidence_score, b.match_confidence_score) AS min_confidence
FROM `veridian_health.patient_master_index` a
JOIN `veridian_health.patient_master_index` b
     ON a.name_hash = b.name_hash
    AND a.master_patient_id < b.master_patient_id
WHERE a.match_confidence_score < 0.85 OR b.match_confidence_score < 0.85
ORDER BY min_confidence ASC;

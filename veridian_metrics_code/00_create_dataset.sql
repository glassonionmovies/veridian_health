-- ============================================================================
--  veridian_metrics — pre-aggregated metric layer for Veridian Health
--  C-suite dashboards (Metric Studio).
-- ----------------------------------------------------------------------------
--  This dataset is built by the 17 rollup jobs in this folder (01..17). Each
--  table is SMALL (a few rows → a few thousand) and is the ONLY thing the
--  ~100 Metric Studio read-queries ever touch — so every metric stays well
--  under the 500 MB / 25 s Metric Studio cap and never scans the 12M-row raw
--  tables in `veridian_health`.
--
--  NO GCP PROJECT IS HARDCODED. Tables are referenced as `veridian_health.x`
--  (read) and `veridian_metrics.y` (write); run with a default project set
--  (`gcloud config set project <ID>`) or `bq query --project_id=<ID>`.
--
--  Run order: 00 (this) → 01..06 facts → 07 exec rollup (reads 01..05) →
--             08..11 dims → 12..17 worklists. See README.md.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS `veridian_metrics`
OPTIONS (
  description = "Pre-aggregated metric layer for Veridian Health C-suite dashboards. Built by rollup jobs from veridian_health; read live by ShareContext Metric Studio. No raw detail."
);

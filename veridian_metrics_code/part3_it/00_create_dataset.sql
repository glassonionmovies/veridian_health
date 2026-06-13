-- ============================================================================
--  veridian_it aggregate layer — IT/Technology (CIO) metrics for Metric Studio.
-- ----------------------------------------------------------------------------
--  Built by the rollup jobs in this folder (18..30) from the veridian_it RAW
--  tables (veridian_health.it_*). Writes into the SAME veridian_metrics dataset
--  as the clinical/financial metrics, so the CIO subject area is a peer layer.
--  Each table is SMALL (read live by Metric Studio; never scans 12M-row raw).
--
--  NO GCP PROJECT HARDCODED. Read `veridian_health.x`, write `veridian_metrics.y`.
--  Run order: 00 (this) → 18,19 dims → 21..25 facts → 26..30 worklists →
--             20 exec rollup (reads the agg layer only). See README.md.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS `veridian_metrics`
OPTIONS (description = "Pre-aggregated metric layer for Veridian Health (clinical, financial, and IT/Technology subject areas). Built by rollup jobs; read live by ShareContext Metric Studio.");

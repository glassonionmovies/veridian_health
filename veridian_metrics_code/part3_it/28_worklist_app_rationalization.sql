-- ============================================================================
--  worklist_app_rationalization   (one row per redundant-capability system)
--  Grain : one row per system_id that shares its capability with >1 system
--  Source: veridian_metrics.dim_it_system (agg dim; reads after build 18),
--          it_cost_ledger + it_vendors lineage already folded into the dim
--  Powers: application-rationalization worklist (consolidation candidates),
--          run-cost concentration / duplicate-capability spend recovery
-- ----------------------------------------------------------------------------
--  Reads veridian_metrics.dim_it_system, so this builds AFTER 18_dim_it_system.
--  Scope = is_redundant (capability_redundancy_count > 1). redundancy_rank is a
--  RANK over run_cost_ttm DESC within capability: rank 1 = highest-investment
--  survivor we KEEP; ranks >1 are RETIRE candidates whose run_cost_ttm is the
--  consolidatable_spend (set to 0 for the survivor — only non-survivor spend is
--  recoverable). run_cost_ttm/redundancy_count come straight from the dim
--  (already TTM-anchored to as_of 2026-06-04); ratios are computed at read time.
--  it_cost_ledger and it_vendors are read transitively via the dim (run_cost_ttm,
--  vendor_name) — not re-aggregated here, to avoid double-counting run cost.
-- ============================================================================

CREATE OR REPLACE TABLE `veridian_metrics.worklist_app_rationalization`
CLUSTER BY capability
AS
WITH params AS (SELECT DATE '2026-06-04' AS as_of),
-- Redundant-capability systems only; rank survivors by run-cost within capability.
redundant AS (
  SELECT
    d.system_id,
    d.system_name,
    d.capability,
    d.vendor_name,
    d.emr_affinity,
    d.capability_redundancy_count                                       AS redundancy_count,
    d.run_cost_ttm,
    d.time_class,
    RANK() OVER (PARTITION BY d.capability ORDER BY d.run_cost_ttm DESC) AS redundancy_rank
  FROM `veridian_metrics.dim_it_system` d
  WHERE d.is_redundant
)
SELECT
  r.system_id,
  r.system_name,
  r.capability,
  r.vendor_name,
  r.emr_affinity,
  r.redundancy_count,
  r.redundancy_rank,
  r.run_cost_ttm,
  -- Only non-survivor (rank > 1) spend is recoverable on consolidation.
  IF(r.redundancy_rank = 1, CAST(0 AS NUMERIC), r.run_cost_ttm)         AS consolidatable_spend,
  r.time_class,
  IF(r.redundancy_rank = 1, 'KEEP', 'RETIRE')                          AS keep_or_retire
FROM redundant r
CROSS JOIN params p;
-- (No ORDER BY: ranked at read time; BQ forbids ORDER BY + CLUSTER BY in CTAS.)

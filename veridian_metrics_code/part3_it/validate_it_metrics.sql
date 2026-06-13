-- Sanity checks for the veridian_it aggregate layer. Run after run_pipeline.sh.
-- 1) every table non-zero
SELECT t, n FROM (
  SELECT 'dim_it_system' t, COUNT(*) n FROM `veridian_metrics.dim_it_system` UNION ALL
  SELECT 'dim_it_asset', COUNT(*) FROM `veridian_metrics.dim_it_asset` UNION ALL
  SELECT 'exec_it_kpi_month', COUNT(*) FROM `veridian_metrics.exec_it_kpi_month` UNION ALL
  SELECT 'fact_it_incident_month', COUNT(*) FROM `veridian_metrics.fact_it_incident_month` UNION ALL
  SELECT 'fact_it_security_month', COUNT(*) FROM `veridian_metrics.fact_it_security_month` UNION ALL
  SELECT 'fact_it_cost_month', COUNT(*) FROM `veridian_metrics.fact_it_cost_month` UNION ALL
  SELECT 'fact_it_servicedesk_month', COUNT(*) FROM `veridian_metrics.fact_it_servicedesk_month` UNION ALL
  SELECT 'fact_it_dex_month', COUNT(*) FROM `veridian_metrics.fact_it_dex_month` UNION ALL
  SELECT 'worklist_open_critical_vulns', COUNT(*) FROM `veridian_metrics.worklist_open_critical_vulns` UNION ALL
  SELECT 'worklist_eol_refresh', COUNT(*) FROM `veridian_metrics.worklist_eol_refresh` UNION ALL
  SELECT 'worklist_app_rationalization', COUNT(*) FROM `veridian_metrics.worklist_app_rationalization` UNION ALL
  SELECT 'worklist_cloud_waste', COUNT(*) FROM `veridian_metrics.worklist_cloud_waste` UNION ALL
  SELECT 'worklist_vendor_renewals', COUNT(*) FROM `veridian_metrics.worklist_vendor_renewals`
) ORDER BY t;
-- 2) exec scorecard: one row per month, no NULL change_failure_rate where changes exist
SELECT COUNT(*) AS months, COUNTIF(change_failure_rate IS NULL) AS null_cfr,
       ROUND(AVG(service_availability_pct),4) AS avg_avail
FROM `veridian_metrics.exec_it_kpi_month`;

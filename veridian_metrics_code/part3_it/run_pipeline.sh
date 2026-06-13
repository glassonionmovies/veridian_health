#!/usr/bin/env bash
# Build the veridian_it aggregate layer (IT/Technology CIO metrics) in dep order.
# No GCP project hardcoded — uses $BQ_PROJECT, else the gcloud default.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${BQ_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
LOCATION="${BQ_LOCATION:-US}"
[[ -z "$PROJECT" ]] && { echo "✗ set BQ_PROJECT or gcloud default project"; exit 1; }
echo "▶ project=$PROJECT location=$LOCATION"
FILES=(
  00_create_dataset.sql
  part1/18_dim_it_system.sql
  part1/19_dim_it_asset.sql
  part1/21_fact_it_incident_month.sql
  part1/22_fact_it_security_month.sql
  part1/23_fact_it_cost_month.sql
  part1/24_fact_it_servicedesk_month.sql
  part1/25_fact_it_dex_month.sql
  part2/26_worklist_open_critical_vulns.sql
  part2/27_worklist_eol_refresh.sql
  part2/28_worklist_app_rationalization.sql
  part2/29_worklist_cloud_waste.sql
  part2/30_worklist_vendor_renewals.sql
  part1/20_exec_it_kpi_month.sql
)
for f in "${FILES[@]}"; do
  [[ -f "$HERE/$f" ]] || { echo "── skip (absent): $f"; continue; }
  echo "── $f ─────────────────────────────"
  bq --location="$LOCATION" --project_id="$PROJECT" query --use_legacy_sql=false --quiet < "$HERE/$f"
done
echo "✓ veridian_it aggregate build complete."

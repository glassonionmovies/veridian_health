# Veridian IT / Technology (CIO) — Aggregate Layer (block diagram)

A business-readable view of how the **`veridian_health.it_*`** raw tables roll up
into the **`veridian_metrics`** CIO aggregate layer and finally into a single
board-ready **Technology Scorecard**. The attribute-level relationships are in
**[ER_diagram.md](ER_diagram.md)**; the build/run brief is in **[HANDOFF.md](HANDOFF.md)**.

**10 raw IT tables → 13 aggregate tables (2 dims · 5 facts · 5 worklists · 1 exec) · 36 months 2023‑06 … 2026‑05 · as_of 2026‑06‑04 · no GCP project hardcoded**

```mermaid
flowchart LR
  subgraph RAW["RAW — veridian_health.it_* (events &amp; inventory, by discipline)"]
    it_systems["it_systems · app/system DIM"]
    it_assets["it_assets · device/host CMDB"]
    it_vendors["it_vendors · vendor DIM"]
    it_incidents["it_incidents · ITSM/SRE"]
    it_vulnerabilities["it_vulnerabilities · SecOps"]
    it_cost_ledger["it_cost_ledger · FinOps/TBM"]
    it_change_requests["it_change_requests · DORA"]
    service_desk_tickets["service_desk_tickets · Service Desk"]
    clinician_ehr_usage["clinician_ehr_usage · DEX"]
    ai_tool_usage["ai_tool_usage · DEX/AI"]
  end

  subgraph AGG["AGGREGATE — veridian_metrics (dims · facts · worklists)"]
    direction TB
    subgraph DIMS["Dimensions (point-in-time)"]
      dim_it_system["dim_it_system · APM/TIME"]
      dim_it_asset["dim_it_asset · ITAM/CMDB"]
    end
    subgraph FACTS["Monthly facts (additive measures)"]
      fact_it_incident_month["fact_it_incident_month"]
      fact_it_security_month["fact_it_security_month"]
      fact_it_cost_month["fact_it_cost_month"]
      fact_it_servicedesk_month["fact_it_servicedesk_month"]
      fact_it_dex_month["fact_it_dex_month"]
    end
    subgraph WORK["Worklists (open action queues)"]
      worklist_open_critical_vulns["open_critical_vulns"]
      worklist_eol_refresh["eol_refresh"]
      worklist_app_rationalization["app_rationalization"]
      worklist_cloud_waste["cloud_waste"]
      worklist_vendor_renewals["vendor_renewals"]
    end
  end

  subgraph EXEC["EXEC — CIO board layer"]
    exec_it_kpi_month["exec_it_kpi_month · monthly KPIs"]
    scorecard{{"Technology Scorecard"}}
  end

  %% RAW -> DIMS
  it_systems --> dim_it_system
  it_vendors --> dim_it_system
  it_incidents --> dim_it_system
  it_cost_ledger --> dim_it_system
  it_assets --> dim_it_asset
  it_vulnerabilities --> dim_it_asset

  %% RAW -> FACTS
  it_incidents --> fact_it_incident_month
  it_vulnerabilities --> fact_it_security_month
  it_cost_ledger --> fact_it_cost_month
  it_change_requests --> fact_it_servicedesk_month
  service_desk_tickets --> fact_it_servicedesk_month
  clinician_ehr_usage --> fact_it_dex_month
  ai_tool_usage --> fact_it_dex_month

  %% RAW -> WORKLISTS
  it_vulnerabilities --> worklist_open_critical_vulns
  it_assets --> worklist_eol_refresh
  it_cost_ledger --> worklist_cloud_waste
  it_cost_ledger --> worklist_vendor_renewals
  dim_it_system -.->|"redundant capability"| worklist_app_rationalization

  %% AGGREGATE -> EXEC (exec reads the agg layer only)
  dim_it_system --> exec_it_kpi_month
  fact_it_incident_month --> exec_it_kpi_month
  fact_it_security_month --> exec_it_kpi_month
  fact_it_cost_month --> exec_it_kpi_month
  fact_it_servicedesk_month --> exec_it_kpi_month
  fact_it_dex_month --> exec_it_kpi_month
  exec_it_kpi_month --> scorecard

  style RAW fill:#fff7ed,stroke:#d97706
  style AGG fill:#effcf9,stroke:#0d9488
  style DIMS fill:#eef2ff,stroke:#6366f1
  style FACTS fill:#eff4ff,stroke:#2563eb
  style WORK fill:#f5f0ff,stroke:#7c3aed
  style EXEC fill:#fff1f3,stroke:#e11d48
```

**Why it matters (CIO):** This layer turns a decade of acquisition-era IT sprawl —
ten event and inventory tables across nine management disciplines (ITSM/SRE, DORA,
SecOps, ITAM/CMDB, APM/TIME, FinOps/TBM, Service Desk, DEX, Vendor) — into one
governed scorecard the board can read in a single sitting. The **facts** carry only
additive measures (ratios computed at read), so availability, MTTR, security
exposure, run-cost, change-failure rate, and digital-employee-experience all roll
up consistently month over month; the **worklists** convert those same signals into
finite, owner-assignable queues — unpatched CRITICALs, end-of-life refresh,
redundant-app consolidation, cloud waste, and vendor renewals due in ≤180 days.
Because every raw table is keyed to the shared facility / department / provider
spine, `exec_it_kpi_month` lets the CIO defend the run-rate, quantify ransomware and
downtime risk in dollars, and tie technology spend to clinical outcome — the gap
between "IT reports tickets" and "IT reports business impact."

# Veridian Health — Synthetic Data Model (block diagram)

A business-readable view of the 26 tables grouped by domain. For a polished,
screenshot-ready version open **[block_diagram.html](block_diagram.html)**; the
attribute-level ER diagram is in **[ER_diagram.md](ER_diagram.md)**.

**26 tables · ~50M rows · 2020–2026 · 3 source EHRs (Epic / Cerner / Meditech) · 10 hospitals · 36 payers · no real PHI**

```mermaid
flowchart LR
  subgraph MASTER["Master &amp; Reference — who / where"]
    facilities
    departments
    providers
    payers
    payer_contracts
    patient_master_index
  end
  subgraph CLIN["Clinical &amp; Encounters — the care"]
    encounters
    orders
    lab_results
    bed_management
    care_management
    prior_authorizations
  end
  subgraph REV["Revenue Cycle — the money"]
    charges
    charge_master
    claims
    appeals_history
    denial_codex
    cdi_queries
  end
  subgraph GROWTH["Access &amp; Growth — top line"]
    appointments_scheduling
    referrals
    price_transparency_rates
  end
  subgraph OPS["Operations &amp; Workforce — the cost"]
    workforce_shifts
    supply_chain_transactions
    quality_safety_events
  end
  subgraph KNOW["Knowledge &amp; Governance — the moat"]
    tribal_knowledge_notes
    system_ledger
  end

  patient_master_index --> encounters --> orders --> charges --> claims --> appeals_history
  encounters --> lab_results
  encounters --> bed_management
  encounters --> care_management
  claims --> denial_codex
  tribal_knowledge_notes -.->|"the play lives here"| denial_codex
  workforce_shifts -.->|"staffing vs harm"| quality_safety_events

  style MASTER fill:#eef2ff,stroke:#6366f1
  style CLIN fill:#effcf9,stroke:#0d9488
  style REV fill:#eff4ff,stroke:#2563eb
  style GROWTH fill:#f5f0ff,stroke:#7c3aed
  style OPS fill:#fff7ed,stroke:#d97706
  style KNOW fill:#fff1f3,stroke:#e11d48
```

**Why it's a demo, not a spreadsheet:** the data is *messy by design* — multi-source IDs
from decades of acquisitions, EMPI duplicates, broken order→charge links, claims billed on
expired contracts, and the institutional knowledge that recovers the money living in a
**retired employee's notes**. The planted "aha" patterns ($1.4M denials, $890K charge gap,
$360K underpayment, 23 stuck inpatients) sit hidden in ~50M rows — surfaced only by reasoning
*across* these domains, which is the ShareContext story.

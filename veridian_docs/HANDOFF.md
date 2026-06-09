# HANDOFF — Build the Veridian Health dataset in BigQuery

**Task for the receiving agent:** generate the Veridian Health synthetic dataset and load it
into BigQuery. Everything is in this folder (`demo-data/veridian_health/`). This doc is the
task brief; **`README.md` is the full reference** — read it if anything here is unclear.

Veridian Health is a *fictional* health system (no real customer name, no real PHI) —
26 tables, ~50M rows at full scale, Jan 2020 → Jun 2026. The generator is **pure Python
stdlib (no pip installs)** and **deterministic** (seed `20260604`).

---

## Prerequisites
- `gcloud` + `bq` CLI installed and authenticated (`gcloud auth login`).
- A GCP project with **BigQuery enabled** (you'll create a dataset named `veridian_health` in it).
- Python 3 (standard library only — nothing to install).

---

## Steps (run in order)

Replace `<PROJECT>` with the target GCP project id.

```bash
cd demo-data/veridian_health
gcloud config set project <PROJECT>

# 1) QUICK CHECK (~10s) — verify the pipeline before the full build.
#    MUST print "17/17 cohort checks PASS". If not, STOP and report (see Troubleshooting).
SC_SCALE=0.01 python3 generate.py
python3 validate_local.py

# 2) FULL BUILD (~50M rows, ~10–20 min; writes a few GB of *.ndjson.gz into ./out/)
python3 generate.py

# 3) LOAD + VALIDATE — creates dataset `veridian_health`, applies the DDL,
#    bq-loads all 26 tables, then runs validate.sql.
./load_to_bq.sh <PROJECT>
```

## Definition of done
`load_to_bq.sh` finishes with a validation table where **every row reads `PASS`**.
Each row checks one planted "aha" against ground truth (68 denials, $890K charge gap,
23 LOS outliers, 220 underpaid claims, 40 EMPI duplicates, …). All-PASS = the dataset is
correct and demo-ready.

---

## Troubleshooting
- **`validate_local.py` is not 17/17** → a *generator* problem; **do not load**. Report which
  check failed. (Don't "fix" it by editing queries — the check is the ground truth.)
- **`bq load` errors on a `.gz` file** → either `gunzip` that file and load the `.ndjson`, or
  use the GCS path below.
- **Validation `FAIL` only on `charge_gap_week_134` / `charge_gap_backlog_5000`** → you ran a
  reduced `SC_SCALE`. Those two are exact only at the full build (`SC_SCALE=1`, i.e. plain
  `python3 generate.py`). Every other check is exact at any scale.
- **Partitioning / schema errors on load** → the tables must be created by the DDL *first*
  (`load_to_bq.sh` does this). `bq load --replace` keeps the existing table's schema +
  partitioning; `--ignore_unknown_values` (already set) drops any extra JSON fields safely.

## Alternative: no `bq` CLI, or very large load (use GCS)
```bash
python3 generate.py                                   # produces ./out/*.ndjson.gz
# create dataset + schema once (console query editor, or bq):
bq query --use_legacy_sql=false < 01_schema.sql
bq query --use_legacy_sql=false < 02_schema_operational.sql
# stage + load from GCS (faster for the full build; bq load reads gzip from gs:// directly):
gsutil -m cp out/*.ndjson.gz gs://<YOUR_BUCKET>/veridian/
for t in out/*.ndjson.gz; do n=$(basename "$t" .ndjson.gz);
  bq load --source_format=NEWLINE_DELIMITED_JSON --ignore_unknown_values --replace \
    veridian_health.$n gs://<YOUR_BUCKET>/veridian/$n.ndjson.gz; done
bq query --use_legacy_sql=false < validate.sql        # all rows should say PASS
```

---

## Guardrails
- **Don't edit `config.py` or `generate.py`** unless a check fails. To change *size*, set the
  `SC_SCALE` env var (don't hand-edit numbers): `0.01` ≈ 0.5M rows, `1.0` ≈ 50M.
- If you must change a table's columns, update the matching DDL in `01_/02_schema*.sql` too —
  `validate_local.py` will catch a generator↔schema mismatch.
- Synthetic data only (no real PHI). Full scale ≈ 15–25 GB storage (~a few $/month); demo
  queries are partition-pruned (cents); generation is local/free.
- `AS_OF_DATE` is a fixed constant (2026-06-04), never wall-clock — the "recent" cohorts
  never drift, so re-running gives the same answers.

---

## What's in the folder (pointers)
| Need | File |
|---|---|
| Full reference / this in more depth | `README.md` |
| What each "aha" is + expected numbers | `USE_CASES.md`, `validate.sql` |
| The 25 strategic / 25 operational questions | `business_questions_*.yaml`, `golden_questions_*.yaml` |
| Show the business what's in the data | `block_diagram.html` (or `.md`) |
| Engineering ER diagram | `ER_diagram.md` (or `.html`) |
| Prove the ahas run / charts aren't flat | `demo_proof.py`, `variation_demo.py` |

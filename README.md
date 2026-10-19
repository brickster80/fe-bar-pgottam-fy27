# "Authorized access, unauthorized movement" — fusion demo

End-to-end Databricks build on `e2-demo-field-eng`, schema **`capmarkets_stg.febar_e2e`**. It correlates Unity Catalog–governed financial-data access (audit, query history, lineage) with identity, endpoint and DLP signals to answer: who accessed sensitive financial data, was it unusual, did it move to an unauthorized destination, and what evidence supports the assessment. Demo flow: [DEMO_SCRIPT.md](DEMO_SCRIPT.md).

| Stage | Asset | Code |
|---|---|---|
| Raw data (synthetic) | Volume `raw_landing`: `uc_audit`, `query_history`, `table_lineage`, `idp`, `endpoint`, `dlp`, `hr`, `devices`, `assets`, `workflows`, `exceptions`, `calendar`; governed stand-in tables | `data_gen/generate_raw.py` |
| Lakeflow | Pipeline `febar-e2e-access-movement` (12 bronze → silver correlation → gold Q2/Q3/Q4) | `src/pipeline/transformations/` |
| Unity Catalog | Tags, masks (`mask_bank_number`), row filter (`filter_forecast`), `gov_access_policy`, live views over `system.access.audit` / `system.query.history` / `system.access.table_lineage`, app SP grants | `src/governance/` |
| ML / GenAI | Isolation Forest `access_movement_iforest@prod` → `gold_user_day_anomaly`; fusion `gold_incident_risk`; `ai_query` → `gold_incident_assessments` | `src/ml/` |
| Lakebase | Project `febar-e2e`; synced `febar_e2e_lakebase.e2e.*` (5 tables); app-owned `e2e_response` | `src/serving/refresh_lakebase_sync.py` |
| Genie | "Authorized Access, Unauthorized Movement" (`01f1cbe0c38c1d129f67a95d56d9ac69`) | `src/genie/build_space.py` |
| AI/BI dashboard | "Authorized Access, Unauthorized Movement - Investigation" (`01f1cbe1f41c13c3b4c1964e652762d9`), Genie-linked | `src/dashboard/` |
| App | `febar-e2e-console` (AppKit: Lakebase + analytics + Genie + embedded dashboard) | `febar-e2e-console/` |
| Orchestration | Job `febar-e2e-access-movement-daily` | `resources/*.yml` |

## Rebuild

```bash
P=e2-demo-field-eng; WH=9d8a677b3c55b8a7
source ../security_context_mvp/.venv/bin/activate
TZ=UTC DATABRICKS_CONFIG_PROFILE=$P python data_gen/generate_raw.py            # raw feeds + governed stand-ins
databricks bundle deploy -p $P && databricks bundle run febar_e2e_daily -p $P    # pipeline -> ML -> GenAI -> Lakebase
DATABRICKS_CONFIG_PROFILE=$P python src/governance/run_sql.py src/governance/apply_governance.sql $WH
cd src/dashboard && python3 build_dashboard.py && cd ../.. && databricks bundle deploy -p $P
cd febar-e2e-console && databricks apps validate -p $P && databricks bundle deploy -p $P && databricks bundle run app -p $P
```

Notes:
- The generator overwrites raw files, and Auto Loader treats them as new. Run a **full refresh** of the pipeline after regenerating.
- Re-running the generator recreates the governed stand-in tables, so re-run `apply_governance.sql` to re-attach the masks and filter.
- The synced tables were created once with `databricks postgres create-synced-table` (SNAPSHOT); the job's last task re-snapshots them.
- App SP `e47b15f2-c014-4729-bcb0-759c6bfc3554`: if the app is recreated, regenerate and re-run `src/governance/grant_app_sp.sql`, plus `GRANT USAGE/SELECT ON SCHEMA e2e` in Lakebase.
- The live system-table views cover 7 days (a 30-day scan of `system.access.audit` is too slow for the app).

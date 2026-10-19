# Databricks notebook source
# MAGIC %md
# MAGIC # Refresh Lakebase synced tables
# MAGIC Re-snapshots the gold SOC tables into Lakebase Postgres (`febar_e2e_lakebase.e2e.*`) so the
# MAGIC investigation console serves the latest incidents, evidence and assessments.

# COMMAND ----------

import time
from databricks.sdk import WorkspaceClient

w = WorkspaceClient()
SYNCED = ["incidents", "assessments", "incident_timeline", "exfil_chains", "access_anomalies"]
pipelines = {}
for t in SYNCED:
    st = w.api_client.do("GET", f"/api/2.0/postgres/synced_tables/febar_e2e_lakebase.e2e.{t}")
    pipelines[t] = st["status"]["pipeline_id"]
    w.pipelines.start_update(pipelines[t])
    print(f"started snapshot refresh for {t} ({pipelines[t]})")

# COMMAND ----------

deadline = time.time() + 1800
pending = dict(pipelines)
while pending and time.time() < deadline:
    time.sleep(20)
    for t, pid in list(pending.items()):
        latest = w.pipelines.get(pid).latest_updates[0]
        if latest.state.value in ("COMPLETED", "FAILED", "CANCELED"):
            print(t, latest.state.value)
            if latest.state.value != "COMPLETED":
                raise RuntimeError(f"sync for {t} ended {latest.state.value}")
            pending.pop(t)
assert not pending, f"timed out waiting for {list(pending)}"

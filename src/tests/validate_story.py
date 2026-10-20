# Databricks notebook source
# MAGIC %md
# MAGIC # Validate the demo story before serving
# MAGIC
# MAGIC Fails the job (and so blocks the Lakebase refresh) if the pipeline, ML or GenAI output no longer tells the
# MAGIC "authorized access, unauthorized movement" story: Alex Morgan's single P1 chain, the evidence timeline,
# MAGIC and the decoys (Priya Shah explained by exception, Kevin Brooks DLP-only, Daniel Okafor no incident).

# COMMAND ----------

dbutils.widgets.text("catalog", "capmarkets_stg")
dbutils.widgets.text("schema", "febar_e2e")
spark.sql("USE CATALOG IDENTIFIER(:c)", args={"c": dbutils.widgets.get("catalog")})
spark.sql("USE SCHEMA IDENTIFIER(:s)", args={"s": dbutils.widgets.get("schema")})

failures, passed = [], []


def check(name, ok, detail=""):
    (passed if ok else failures).append(f"{name}{': ' + str(detail) if detail else ''}")


def rows(sql):
    return [r.asDict() for r in spark.sql(sql).collect()]

# COMMAND ----------

# MAGIC %md
# MAGIC ## Every layer produced data

# COMMAND ----------

for t in ["bronze_uc_audit", "bronze_query_history", "bronze_table_lineage", "bronze_idp_signins", "bronze_endpoint_events",
          "bronze_dlp_events", "silver_sensitive_access", "silver_identity_sessions", "gold_access_anomalies",
          "gold_exfil_chains", "gold_incidents", "gold_incident_timeline", "gold_user_daily_features",
          "gold_user_day_anomaly", "gold_incident_risk", "gold_incident_assessments"]:
    n = spark.table(t).count()
    check(f"{t} has rows", n > 0, n)

# Correlation must link most sensitive statements to a device via audit IP -> IdP session
linked = rows("SELECT avg(CASE WHEN device_id IS NOT NULL THEN 1 ELSE 0 END) AS p FROM silver_sensitive_access")[0]["p"]
check("sensitive access linked to a device >= 90%", linked >= 0.9, round(linked, 3))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Q1-Q4 for Alex Morgan

# COMMAND ----------

alex = rows("SELECT * FROM gold_incident_risk WHERE incident_id = 'INC-20260924-E-0042'")
check("Alex incident exists", len(alex) == 1)
if alex:
    a = alex[0]
    check("Q1 asset is vendor_bank_accounts", a["primary_asset"] == "finance_prod.treasury.vendor_bank_accounts", a["primary_asset"])
    check("Q1 device is the loaner", a["device_hostname"] == "LOANER-NYC-07", a["device_hostname"])
    check("Q2 480,000 rows", a["produced_rows"] == 480000, a["produced_rows"])
    check("Q2 >= 10x self and peers", a["max_ratio_vs_self"] >= 10 and a["max_ratio_vs_peers"] >= 10,
          (a["max_ratio_vs_self"], a["max_ratio_vs_peers"]))
    check("Q3 uploaded to unauthorized destination", a["chain_stage"] == "uploaded_unauthorized", a["chain_stage"])
    check("priority P1", a["priority"] == "P1", a["priority"])

steps = [r["local_hhmm"] for r in rows("SELECT local_hhmm FROM gold_incident_timeline WHERE incident_id = 'INC-20260924-E-0042' ORDER BY step")]
check("Q4 timeline 21:40-21:55", steps == ["21:40", "21:43", "21:46", "21:49", "21:53", "21:55"], steps)

unauth = rows("SELECT count(*) AS n FROM gold_incidents WHERE chain_stage = 'uploaded_unauthorized'")[0]["n"]
p1 = rows("SELECT count(*) AS n FROM gold_incident_risk WHERE priority = 'P1'")[0]["n"]
check("exactly one unauthorized movement", unauth == 1, unauth)
check("exactly one P1", p1 == 1, p1)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Decoys and GenAI assessment

# COMMAND ----------

priya = rows("SELECT priority, exception_ticket, triage_recommendation FROM gold_incident_risk WHERE employee_id = 'E-0095'")
check("Priya explained by exception (P4, EXC-4471)",
      len(priya) == 1 and priya[0]["priority"] == "P4" and priya[0]["exception_ticket"] == "EXC-4471", priya)
kevin = rows("SELECT chain_stage FROM gold_incidents WHERE employee_id = 'E-0150'")
check("Kevin is DLP-only", [k["chain_stage"] for k in kevin] == ["dlp_only_no_sensitive_lineage"], kevin)
daniel = rows("SELECT count(*) AS n FROM gold_incidents WHERE employee_id = 'E-0118'")[0]["n"]
check("Daniel (new managed laptop) has no incident", daniel == 0, daniel)

LABELS = {"Insider misuse", "Account or device compromise", "Undetermined - needs more evidence", "Benign / explained"}
assess = rows("SELECT incident_id, leading_hypothesis, length(assessment) AS len FROM gold_incident_assessments")
check("Alex has a GenAI assessment", any(r["incident_id"] == "INC-20260924-E-0042" and r["len"] > 200 for r in assess))
bad = [r for r in assess if r["leading_hypothesis"] not in LABELS]
check("hypothesis labels are valid", not bad, bad)

# COMMAND ----------

print("\n".join(["PASS " + p for p in passed] + ["FAIL " + f for f in failures]))
assert not failures, f"{len(failures)} story checks failed: {failures}"
dbutils.notebook.exit(f"{len(passed)} checks passed")

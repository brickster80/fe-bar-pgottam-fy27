# Databricks notebook source
# MAGIC %md
# MAGIC # Q4 - What evidence supports the threat assessment?
# MAGIC
# MAGIC 1. **Fusion**: the rules evidence score from `gold_incidents` (60%) is fused with the Isolation Forest score
# MAGIC    for the same employee-day (40%) into `gold_incident_risk` with a P1-P4 priority.
# MAGIC 2. **GenAI assessment**: `ai_query` (Claude Sonnet) weighs **H1 insider misuse** against **H2 account or device
# MAGIC    compromise** for every P1/P2, exception-explained and DLP-only incident, and writes `gold_incident_assessments`.

# COMMAND ----------

dbutils.widgets.text("catalog", "capmarkets_stg")
dbutils.widgets.text("schema", "febar_e2e")
spark.sql("USE CATALOG IDENTIFIER(:c)", args={"c": dbutils.widgets.get("catalog")})
spark.sql("USE SCHEMA IDENTIFIER(:s)", args={"s": dbutils.widgets.get("schema")})

# COMMAND ----------

# MAGIC %md
# MAGIC ## Fusion: rules + ML -> priority

# COMMAND ----------

spark.sql("""
CREATE OR REPLACE TABLE gold_incident_risk
COMMENT 'Incident risk: rules evidence score fused with the ML anomaly score for the same employee-day'
AS SELECT i.*, a.anomaly_score, a.is_anomaly, a.top_drivers,
  round(least(100, i.rules_risk_score * 0.6 + coalesce(a.anomaly_score, 0) * 100 * 0.4
        + CASE WHEN a.is_anomaly AND i.is_unauthorized_destination THEN 10 ELSE 0 END), 1) AS fused_risk,
  CASE WHEN i.exception_ticket IS NOT NULL THEN 'P4'
       WHEN least(100, i.rules_risk_score * 0.6 + coalesce(a.anomaly_score, 0) * 40) >= 75 THEN 'P1'
       WHEN least(100, i.rules_risk_score * 0.6 + coalesce(a.anomaly_score, 0) * 40) >= 45 THEN 'P2'
       WHEN least(100, i.rules_risk_score * 0.6 + coalesce(a.anomaly_score, 0) * 40) >= 25 THEN 'P3' ELSE 'P4' END AS priority
FROM gold_incidents i
LEFT JOIN gold_user_day_anomaly a
  ON a.employee_id = i.employee_id AND a.activity_date = i.incident_date
""")
display(spark.sql("SELECT priority, count(*) AS incidents FROM gold_incident_risk GROUP BY priority ORDER BY priority"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## GenAI threat assessment with competing hypotheses

# COMMAND ----------

spark.sql(r"""
CREATE OR REPLACE TABLE gold_incident_assessments
COMMENT 'GenAI threat assessment (ai_query, Claude Sonnet): weighs insider misuse vs account/device compromise, ATT&CK narrative, recommended response'
AS WITH ev AS (
  SELECT r.*,
    (SELECT array_join(collect_list(concat(t.local_hhmm, ' | ', t.source, ' | ', t.observation)), '\n')
       FROM (SELECT * FROM gold_incident_timeline x WHERE x.incident_id = r.incident_id ORDER BY step) t) AS timeline_text
  FROM gold_incident_risk r
  WHERE r.priority IN ('P1', 'P2') OR r.exception_ticket IS NOT NULL OR r.chain_stage = 'dlp_only_no_sensitive_lineage'
),
ctx AS (
  SELECT *, concat(
    'Employee: ', full_name, ' (', employee_id, '), ', role, ', ', department, '. Local timezone ', timezone, '.\n',
    'Governed asset: ', coalesce(primary_asset, 'none'), '. Rows returned: ', coalesce(cast(produced_rows AS STRING), 'n/a'),
    ' vs employee median daily ', coalesce(cast(user_median_daily_rows AS STRING), 'n/a'),
    ' (', coalesce(cast(max_ratio_vs_self AS STRING), 'n/a'), 'x self, ', coalesce(cast(max_ratio_vs_peers AS STRING), 'n/a'), 'x peers).\n',
    'First-ever access to restricted asset: ', first_access_restricted, '. Off-hours: ', off_hours_sensitive,
    '. Device: ', coalesce(device_hostname, 'n/a'), ' assigned to employee: ', NOT unassigned_device, '.\n',
    'Chain stage: ', chain_stage, '. Destination: ', coalesce(concat(upload_app, ' ', instance_type, ' ', destination_account), 'none'),
    '. Exception ticket: ', coalesce(exception_ticket, 'none'), '.\n',
    'ML anomaly score (0-1): ', coalesce(cast(anomaly_score AS STRING), 'n/a'), '; drivers: ', coalesce(array_join(top_drivers, ', '), 'none'), '.\n',
    'Rules risk ', rules_risk_score, ', fused risk ', fused_risk, ', ATT&CK: ', array_join(attack_techniques, ', '), '.\n',
    'Indicators favouring account/device COMPROMISE: ', coalesce(nullif(array_join(compromise_indicators, '; '), ''), 'none'), '.\n',
    'Indicators favouring employee MISUSE of legitimate access: ', coalesce(nullif(array_join(misuse_indicators, '; '), ''), 'none'), '.\n',
    'Mitigating factors: ', coalesce(nullif(array_join(mitigating_factors, '; '), ''), 'none'), '.\n',
    'Evidence timeline (local time | source | observation):\n', coalesce(timeline_text, 'none')) AS evidence
  FROM ev
)
SELECT incident_id, employee_id, full_name, department, role, priority, fused_risk, evidence,
  ai_query('databricks-claude-sonnet-4-6', concat(
    'You are a Tier-3 insider-risk and SOC analyst at a financial company. Write a threat assessment from the evidence. ',
    'Do NOT assume the employee is malicious. Evaluate two competing hypotheses: (H1) the employee is misusing legitimate access; ',
    '(H2) someone compromised the employee''s account or device. If the evidence is benign, say so plainly. ',
    'Use exactly these markdown sections: **Verdict** (one sentence), **Who and what** (governed asset, sensitivity, rows), ',
    '**Unusual vs self and peers**, **Did data leave?** (file + destination, approved or not), ',
    '**H1 - Insider misuse** (evidence for / against), **H2 - Account or device compromise** (evidence for / against), ',
    '**ATT&CK narrative** (bullets), **Recommended response** (3-5 bullets for analyst approval, most urgent first, ',
    'proportionate to the evidence; preserve evidence before contacting the employee). ',
    'Only use facts in the evidence. Under 300 words.\n\nEVIDENCE:\n', evidence)) AS assessment,
  trim(ai_query('databricks-claude-sonnet-4-6', concat(
    'Based on the evidence, which hypothesis is currently better supported? Reply with exactly one of: ',
    'Insider misuse | Account or device compromise | Undetermined - needs more evidence | Benign / explained. ',
    'Choose Undetermined when material indicators exist for BOTH misuse and compromise and nothing decisive separates them ',
    '(e.g. no device forensics, no employee interview yet). Reply with the label only.\n\nEVIDENCE:\n', evidence))) AS leading_hypothesis,
  current_timestamp() AS generated_at
FROM ctx
""")
display(spark.sql("SELECT full_name, priority, fused_risk, leading_hypothesis FROM gold_incident_assessments ORDER BY fused_risk DESC"))

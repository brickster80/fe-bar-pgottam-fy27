-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Silver - normalize identities and correlate access (Q1)
-- MAGIC
-- MAGIC **Q1 - Who accessed sensitive financial data?**
-- MAGIC
-- MAGIC The query has no device and the endpoint has no query. The audit `commandSubmit` source IP bridges the statement to the IdP session, and the session gives the device.
-- MAGIC `silver_sensitive_access` = query history ⋈ lineage ⋈ audit IP ⋈ IdP session ⋈ HR ⋈ asset registry ⋈ workflow / exception / calendar.
-- MAGIC
-- MAGIC This notebook is a Lakeflow pipeline source; run it through pipeline `febar-e2e-access-movement`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Identity sessions

-- COMMAND ----------

-- Identity context per sign-in: is this device known for this employee?
CREATE OR REFRESH MATERIALIZED VIEW silver_identity_sessions
COMMENT 'IdP sign-ins enriched with CMDB device assignment and first-seen device history per employee'
TBLPROPERTIES ('quality' = 'silver')
AS WITH s AS (
  SELECT i.*, e.employee_id, e.full_name, e.department, e.timezone,
         min(i.signin_time) OVER (PARTITION BY i.user_email, i.device_id) AS device_first_seen
  FROM silver_idp_signins i JOIN silver_employees e ON i.user_email = e.email
)
SELECT s.*, from_utc_timestamp(s.signin_time, s.timezone) AS signin_local,
  d.hostname AS device_hostname, d.device_type, d.managed AS device_managed, d.assignment_status,
  d.assigned_employee_id,
  coalesce(d.assigned_employee_id = s.employee_id, false) AS device_assigned_to_user,
  s.signin_time = s.device_first_seen AND s.signin_time > timestamp'2026-07-15' AS is_new_device_for_user
FROM s LEFT JOIN silver_devices d ON s.device_id = d.device_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Sensitive access

-- COMMAND ----------

-- One row per statement: query history x lineage x asset registry x HR x audit (source IP) x IdP session (device)
CREATE OR REFRESH MATERIALIZED VIEW silver_sensitive_access
COMMENT 'Who accessed which governed asset: statement-level access with sensitivity, local time, device, entitlement and workflow context'
CLUSTER BY (access_date, employee_id)
TBLPROPERTIES ('quality' = 'silver')
AS WITH q AS (
  SELECT q.*, l.source_table_full_name AS asset_full_name
  FROM silver_query_history q JOIN silver_table_lineage l ON q.statement_id = l.statement_id
),
ip AS (
  SELECT statement_id, first(source_ip) AS source_ip, first(user_agent) AS user_agent
  FROM silver_uc_audit WHERE action_name = 'commandSubmit' GROUP BY statement_id
),
j AS (
  SELECT q.*, ip.source_ip, ip.user_agent, e.employee_id, e.full_name, e.department, e.role, e.timezone,
         a.sensitivity, a.sensitivity_rank, a.content, a.expected_use, a.regulation, a.physical_table,
         array_contains(a.granted_departments, e.department) AS is_granted_department,
         from_utc_timestamp(q.start_time, e.timezone) AS start_local
  FROM q
  JOIN silver_employees e ON q.executed_by = e.email
  JOIN silver_asset_registry a ON q.asset_full_name = a.asset_full_name
  LEFT JOIN ip ON q.statement_id = ip.statement_id
),
sess AS (
  SELECT j.statement_id, s.signin_id, s.device_id, s.device_hostname, s.device_assigned_to_user,
         s.is_new_device_for_user, s.risk_level, s.network, s.factor, s.signin_time,
         row_number() OVER (PARTITION BY j.statement_id ORDER BY s.signin_time DESC) AS rn
  FROM j JOIN silver_identity_sessions s
    ON s.user_email = j.executed_by AND s.src_ip = j.source_ip
   AND s.signin_time <= j.start_time AND s.signin_time >= j.start_time - INTERVAL 16 HOURS
),
wf AS (
  SELECT asset_full_name, explode(approved_departments) AS department, first(workflow_id) AS workflow_id
  FROM silver_workflows GROUP BY ALL
)
SELECT j.statement_id, j.session_id, j.executed_by AS user_email, j.employee_id, j.full_name, j.department, j.role,
  j.asset_full_name, j.physical_table, j.sensitivity, j.sensitivity_rank, j.content, j.expected_use, j.regulation,
  j.start_time, j.end_time, j.start_local, to_date(j.start_local) AS access_date, hour(j.start_local) AS local_hour,
  j.execution_status, j.produced_rows, j.read_bytes,
  CASE WHEN j.produced_rows > 0 THEN j.read_bytes / j.produced_rows END AS bytes_per_row,
  j.client_application, j.statement_text, j.source_ip, j.user_agent,
  s.signin_id, s.device_id, s.device_hostname, coalesce(s.device_assigned_to_user, false) AS device_assigned_to_user,
  coalesce(s.is_new_device_for_user, false) AS is_new_device_session, s.risk_level AS signin_risk, s.network, s.factor, s.signin_time,
  j.is_granted_department,
  wf.workflow_id IS NOT NULL AS has_approved_workflow, wf.workflow_id,
  x.ticket_id AS exception_ticket,
  coalesce(c.is_close_period, false) AS is_close_period,
  (hour(j.start_local) < 7 OR hour(j.start_local) >= 20) AS is_off_hours
FROM j
LEFT JOIN sess s ON j.statement_id = s.statement_id AND s.rn = 1
LEFT JOIN wf ON wf.asset_full_name = j.asset_full_name AND wf.department = j.department
LEFT JOIN silver_exceptions x ON x.employee_id = j.employee_id AND x.asset_full_name = j.asset_full_name
  AND x.status = 'approved' AND to_date(j.start_local) BETWEEN x.valid_from AND x.valid_to
LEFT JOIN silver_calendar c ON c.cal_date = to_date(j.start_local);
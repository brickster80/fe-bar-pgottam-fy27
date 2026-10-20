-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Silver - normalize each source
-- MAGIC
-- MAGIC Typed, cleaned, one table per source, with expectations. Identities are normalized to the employee email / employee_id.
-- MAGIC
-- MAGIC This notebook is a Lakeflow pipeline source; run it through pipeline `febar-e2e-access-movement`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Databricks evidence

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE silver_uc_audit (
  CONSTRAINT valid_identity EXPECT (user_email IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Databricks audit: identity, action, source IP, governed table or statement, UC response'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT request_id, to_timestamp(event_time) AS event_time, cast(event_date AS DATE) AS event_date,
  service_name, action_name, user_identity.email AS user_email,
  request_params.full_name_arg AS table_full_name, request_params.commandId AS statement_id,
  cast(response.status_code AS INT) AS status_code, response.error_message AS error_message,
  source_ip_address AS source_ip, user_agent
FROM STREAM(bronze_uc_audit);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE silver_query_history (
  CONSTRAINT valid_statement EXPECT (statement_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_identity  EXPECT (executed_by IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT sane_rows       EXPECT (produced_rows >= 0)
)
COMMENT 'Query execution evidence: who ran which statement, from which client, how many rows it returned'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT statement_id, session_id, executed_by, execution_status, compute.warehouse_id AS warehouse_id,
  statement_text, statement_type, error_message, client_application,
  cast(total_duration_ms AS BIGINT) AS total_duration_ms,
  to_timestamp(start_time) AS start_time, to_timestamp(end_time) AS end_time,
  cast(read_rows AS BIGINT) AS read_rows, cast(produced_rows AS BIGINT) AS produced_rows, cast(read_bytes AS BIGINT) AS read_bytes
FROM STREAM(bronze_query_history);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE silver_table_lineage (
  CONSTRAINT valid_source EXPECT (source_table_full_name IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Lineage: which governed source table each statement read'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT statement_id, entity_type, source_table_full_name, source_type, target_table_full_name, target_type,
  created_by, to_timestamp(event_time) AS event_time
FROM STREAM(bronze_table_lineage);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Identity, endpoint and DLP

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE silver_idp_signins (
  CONSTRAINT valid_identity EXPECT (user_email IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Identity provider sign-ins: device, source IP, network, factor, IdP risk'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT uuid AS signin_id, to_timestamp(published) AS signin_time, email AS user_email, device_id, src_ip,
  session_id, network, factor, outcome, risk_level, cast(device_trusted AS BOOLEAN) AS device_trusted
FROM STREAM(bronze_idp_signins);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE silver_endpoint_files (
  CONSTRAINT valid_hash EXPECT (sha256 IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Endpoint file materialization: device, creating process, file, hash, size'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT event_id, to_timestamp(timestamp) AS file_time, device_id, email AS user_email, lower(process_name) AS process_name,
  file_path, file_name, lower(sha256) AS sha256, cast(size_bytes AS BIGINT) AS size_bytes
FROM STREAM(bronze_endpoint_events);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE silver_dlp_events (
  CONSTRAINT valid_hash EXPECT (sha256 IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'DLP / CASB uploads: destination app, instance (corporate vs personal), account, hash, bytes, DLP profile'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT event_id, to_timestamp(timestamp) AS upload_time, email AS user_email, device_id, app, instance_type,
  destination, destination_account, file_name, lower(sha256) AS sha256, cast(bytes AS BIGINT) AS bytes,
  activity, action, outcome, policy, dlp_profile,
  NOT (instance_type = 'corporate' AND destination_account = 'tenant:halcyonfin') AS is_unapproved_destination
FROM STREAM(bronze_dlp_events);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Business context

-- COMMAND ----------

CREATE OR REFRESH MATERIALIZED VIEW silver_employees (
  CONSTRAINT valid_email EXPECT (email LIKE '%@%') ON VIOLATION DROP ROW
)
COMMENT 'Business context: employee department, role, office, local timezone, manager'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT employee_id, full_name, email, department, role, office, timezone, manager_id
FROM bronze_hr_employees
QUALIFY row_number() OVER (PARTITION BY employee_id ORDER BY _ingested_at DESC, _source_file DESC) = 1;

-- COMMAND ----------

CREATE OR REFRESH MATERIALIZED VIEW silver_devices
COMMENT 'CMDB devices: assignment to employee, managed state, loaner pool'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT device_id, hostname, device_type, cast(managed AS BOOLEAN) AS managed, assigned_employee_id,
  assignment_status, cast(assigned_since AS DATE) AS assigned_since
FROM bronze_devices
QUALIFY row_number() OVER (PARTITION BY device_id ORDER BY _ingested_at DESC, _source_file DESC) = 1;

-- COMMAND ----------

CREATE OR REFRESH MATERIALIZED VIEW silver_asset_registry
COMMENT 'Governed financial assets: sensitivity, expected use, regulation, departments granted access, physical UC table'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT asset_full_name, physical_table, sensitivity, cast(sensitivity_rank AS INT) AS sensitivity_rank, content,
  expected_use, regulation, split(granted_departments, ';') AS granted_departments
FROM bronze_asset_registry
QUALIFY row_number() OVER (PARTITION BY asset_full_name ORDER BY _ingested_at DESC) = 1;

-- COMMAND ----------

CREATE OR REFRESH MATERIALIZED VIEW silver_workflows
COMMENT 'Approved workflows: which departments may use which governed asset, and under what conditions'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT workflow_id, workflow_name, asset_full_name, split(approved_departments, ';') AS approved_departments, conditions
FROM bronze_workflows
QUALIFY row_number() OVER (PARTITION BY workflow_id ORDER BY _ingested_at DESC) = 1;

-- COMMAND ----------

CREATE OR REFRESH MATERIALIZED VIEW silver_exceptions
COMMENT 'Approved access exception tickets'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT ticket_id, employee_id, asset_full_name, justification, cast(valid_from AS DATE) AS valid_from,
  cast(valid_to AS DATE) AS valid_to, status, approver
FROM bronze_exceptions
QUALIFY row_number() OVER (PARTITION BY ticket_id ORDER BY _ingested_at DESC) = 1;

-- COMMAND ----------

CREATE OR REFRESH MATERIALIZED VIEW silver_calendar
COMMENT 'Reporting calendar incl. month-end close periods'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT cast(cal_date AS DATE) AS cal_date, cast(is_business_day AS BOOLEAN) AS is_business_day,
  cast(is_close_period AS BOOLEAN) AS is_close_period, period_label
FROM bronze_calendar
QUALIFY row_number() OVER (PARTITION BY cal_date ORDER BY _ingested_at DESC) = 1;

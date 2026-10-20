-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Bronze - ingest raw security and business feeds
-- MAGIC
-- MAGIC Auto Loader (`STREAM read_files`) over the 12 feeds in `/Volumes/capmarkets_stg/febar_e2e/raw_landing/`.
-- MAGIC Databricks evidence is shaped like `system.access.audit`, `system.query.history` and `system.access.table_lineage`;
-- MAGIC external evidence comes from the IdP (Okta), endpoint (CrowdStrike EDR) and DLP (Netskope); business context from HR, CMDB, the asset registry, approved workflows, exception tickets and the reporting calendar.
-- MAGIC
-- MAGIC This notebook is a Lakeflow pipeline source; run it through pipeline `febar-e2e-access-movement`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Databricks evidence

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_uc_audit
COMMENT 'Databricks audit log export (system.access.audit shape)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/uc_audit/', format => 'json', inferColumnTypes => true);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_query_history
COMMENT 'Databricks query history export (system.query.history shape)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/query_history/', format => 'json', inferColumnTypes => true);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_table_lineage
COMMENT 'Databricks table lineage export (system.access.table_lineage shape)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/table_lineage/', format => 'json', inferColumnTypes => true, schemaHints => 'target_table_full_name STRING, target_type STRING');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Identity, endpoint and DLP

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_idp_signins
COMMENT 'Identity provider (Okta) sign-in events: device, IP, factor, risk'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/idp/', format => 'json', inferColumnTypes => true);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_endpoint_events
COMMENT 'EDR (CrowdStrike) file-creation telemetry: device, process, file, sha256'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/endpoint/', format => 'json', inferColumnTypes => true);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_dlp_events
COMMENT 'DLP / CASB (Netskope) upload events: destination instance, account, sha256, bytes'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/dlp/', format => 'json', inferColumnTypes => true, schemaHints => 'dlp_profile STRING');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Business context

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_hr_employees
COMMENT 'HR employee roster: department, role, office, timezone, manager'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/hr/', format => 'csv', header => true);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_devices
COMMENT 'CMDB device inventory: assignment, managed, loaner pool'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/devices/', format => 'csv', header => true);

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_asset_registry
COMMENT 'Governed asset registry: sensitivity, expected use, regulation, granted departments'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/assets/', format => 'json');

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_workflows
COMMENT 'Approved business workflows per governed asset'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/workflows/', format => 'json');

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_exceptions
COMMENT 'Access exception tickets (ServiceNow)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/exceptions/', format => 'json');

-- COMMAND ----------

CREATE OR REFRESH STREAMING TABLE bronze_calendar
COMMENT 'Reporting calendar incl. month-end close'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/calendar/', format => 'csv', header => true);

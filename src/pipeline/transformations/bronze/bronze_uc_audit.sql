CREATE OR REFRESH STREAMING TABLE bronze_uc_audit
COMMENT 'Databricks audit log export (system.access.audit shape)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/uc_audit/', format => 'json', inferColumnTypes => true);

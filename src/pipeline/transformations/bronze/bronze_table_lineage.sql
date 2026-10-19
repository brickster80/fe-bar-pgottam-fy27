CREATE OR REFRESH STREAMING TABLE bronze_table_lineage
COMMENT 'Databricks table lineage export (system.access.table_lineage shape)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/table_lineage/', format => 'json', inferColumnTypes => true, schemaHints => 'target_table_full_name STRING, target_type STRING');

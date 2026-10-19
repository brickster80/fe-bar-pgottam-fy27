CREATE OR REFRESH STREAMING TABLE bronze_query_history
COMMENT 'Databricks query history export (system.query.history shape)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/query_history/', format => 'json', inferColumnTypes => true);

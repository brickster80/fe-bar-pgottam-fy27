CREATE OR REFRESH STREAMING TABLE bronze_workflows
COMMENT 'Approved business workflows per governed asset'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/workflows/', format => 'json');

CREATE OR REFRESH STREAMING TABLE bronze_exceptions
COMMENT 'Access exception tickets (ServiceNow)'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/exceptions/', format => 'json');

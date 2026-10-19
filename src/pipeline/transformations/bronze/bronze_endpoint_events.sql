CREATE OR REFRESH STREAMING TABLE bronze_endpoint_events
COMMENT 'EDR (CrowdStrike) file-creation telemetry: device, process, file, sha256'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/endpoint/', format => 'json', inferColumnTypes => true);

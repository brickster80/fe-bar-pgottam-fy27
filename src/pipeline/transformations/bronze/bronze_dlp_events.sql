CREATE OR REFRESH STREAMING TABLE bronze_dlp_events
COMMENT 'DLP / CASB (Netskope) upload events: destination instance, account, sha256, bytes'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/dlp/', format => 'json', inferColumnTypes => true, schemaHints => 'dlp_profile STRING');

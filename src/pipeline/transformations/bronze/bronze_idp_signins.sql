CREATE OR REFRESH STREAMING TABLE bronze_idp_signins
COMMENT 'Identity provider (Okta) sign-in events: device, IP, factor, risk'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/idp/', format => 'json', inferColumnTypes => true);

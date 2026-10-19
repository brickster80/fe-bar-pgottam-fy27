CREATE OR REFRESH STREAMING TABLE bronze_devices
COMMENT 'CMDB device inventory: assignment, managed, loaner pool'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/devices/', format => 'csv', header => true);

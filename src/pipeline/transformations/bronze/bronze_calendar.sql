CREATE OR REFRESH STREAMING TABLE bronze_calendar
COMMENT 'Reporting calendar incl. month-end close'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/calendar/', format => 'csv', header => true);

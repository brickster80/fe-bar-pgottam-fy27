CREATE OR REFRESH STREAMING TABLE bronze_hr_employees
COMMENT 'HR employee roster: department, role, office, timezone, manager'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/hr/', format => 'csv', header => true);

CREATE OR REFRESH STREAMING TABLE bronze_asset_registry
COMMENT 'Governed asset registry: sensitivity, expected use, regulation, granted departments'
TBLPROPERTIES ('quality' = 'bronze')
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingested_at
FROM STREAM read_files('/Volumes/capmarkets_stg/febar_e2e/raw_landing/assets/', format => 'json');

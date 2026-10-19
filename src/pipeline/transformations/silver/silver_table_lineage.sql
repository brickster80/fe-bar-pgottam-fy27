CREATE OR REFRESH STREAMING TABLE silver_table_lineage (
  CONSTRAINT valid_source EXPECT (source_table_full_name IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Lineage: which governed source table each statement read'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT statement_id, entity_type, source_table_full_name, source_type, target_table_full_name, target_type,
  created_by, to_timestamp(event_time) AS event_time
FROM STREAM(bronze_table_lineage);

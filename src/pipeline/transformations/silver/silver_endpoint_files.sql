CREATE OR REFRESH STREAMING TABLE silver_endpoint_files (
  CONSTRAINT valid_hash EXPECT (sha256 IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Endpoint file materialization: device, creating process, file, hash, size'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT event_id, to_timestamp(timestamp) AS file_time, device_id, email AS user_email, lower(process_name) AS process_name,
  file_path, file_name, lower(sha256) AS sha256, cast(size_bytes AS BIGINT) AS size_bytes
FROM STREAM(bronze_endpoint_events);

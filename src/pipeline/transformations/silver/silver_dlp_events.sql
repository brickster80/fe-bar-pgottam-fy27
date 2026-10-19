CREATE OR REFRESH STREAMING TABLE silver_dlp_events (
  CONSTRAINT valid_hash EXPECT (sha256 IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'DLP / CASB uploads: destination app, instance (corporate vs personal), account, hash, bytes, DLP profile'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT event_id, to_timestamp(timestamp) AS upload_time, email AS user_email, device_id, app, instance_type,
  destination, destination_account, file_name, lower(sha256) AS sha256, cast(bytes AS BIGINT) AS bytes,
  activity, action, outcome, policy, dlp_profile,
  NOT (instance_type = 'corporate' AND destination_account = 'tenant:halcyonfin') AS is_unapproved_destination
FROM STREAM(bronze_dlp_events);

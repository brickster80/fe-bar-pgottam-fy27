CREATE OR REFRESH STREAMING TABLE silver_uc_audit (
  CONSTRAINT valid_identity EXPECT (user_email IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Databricks audit: identity, action, source IP, governed table or statement, UC response'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT request_id, to_timestamp(event_time) AS event_time, cast(event_date AS DATE) AS event_date,
  service_name, action_name, user_identity.email AS user_email,
  request_params.full_name_arg AS table_full_name, request_params.commandId AS statement_id,
  cast(response.status_code AS INT) AS status_code, response.error_message AS error_message,
  source_ip_address AS source_ip, user_agent
FROM STREAM(bronze_uc_audit);

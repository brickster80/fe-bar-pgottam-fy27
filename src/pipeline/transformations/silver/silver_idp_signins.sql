CREATE OR REFRESH STREAMING TABLE silver_idp_signins (
  CONSTRAINT valid_identity EXPECT (user_email IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Identity provider sign-ins: device, source IP, network, factor, IdP risk'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT uuid AS signin_id, to_timestamp(published) AS signin_time, email AS user_email, device_id, src_ip,
  session_id, network, factor, outcome, risk_level, cast(device_trusted AS BOOLEAN) AS device_trusted
FROM STREAM(bronze_idp_signins);

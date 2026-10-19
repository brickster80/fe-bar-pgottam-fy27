-- Identity context per sign-in: is this device known for this employee?
CREATE OR REFRESH MATERIALIZED VIEW silver_identity_sessions
COMMENT 'IdP sign-ins enriched with CMDB device assignment and first-seen device history per employee'
TBLPROPERTIES ('quality' = 'silver')
AS WITH s AS (
  SELECT i.*, e.employee_id, e.full_name, e.department, e.timezone,
         min(i.signin_time) OVER (PARTITION BY i.user_email, i.device_id) AS device_first_seen
  FROM silver_idp_signins i JOIN silver_employees e ON i.user_email = e.email
)
SELECT s.*, from_utc_timestamp(s.signin_time, s.timezone) AS signin_local,
  d.hostname AS device_hostname, d.device_type, d.managed AS device_managed, d.assignment_status,
  d.assigned_employee_id,
  coalesce(d.assigned_employee_id = s.employee_id, false) AS device_assigned_to_user,
  s.signin_time = s.device_first_seen AND s.signin_time > timestamp'2026-07-15' AS is_new_device_for_user
FROM s LEFT JOIN silver_devices d ON s.device_id = d.device_id;

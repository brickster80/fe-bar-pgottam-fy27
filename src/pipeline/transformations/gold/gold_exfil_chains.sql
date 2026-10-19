-- Q3: Did the data move to an unauthorized destination?  access -> local file -> upload
CREATE OR REFRESH MATERIALIZED VIEW gold_exfil_chains
COMMENT 'Correlated chains: sensitive query -> file materialized on the same device by the client process -> upload of the same file hash'
TBLPROPERTIES ('quality' = 'gold')
AS WITH a AS (
  SELECT * FROM silver_sensitive_access
  WHERE execution_status = 'FINISHED' AND sensitivity_rank >= 2 AND produced_rows > 0 AND device_id IS NOT NULL
),
f AS (
  SELECT a.statement_id, e.event_id AS file_event_id, e.file_time, e.process_name, e.file_path, e.file_name, e.sha256, e.size_bytes,
         round(e.size_bytes / greatest(a.read_bytes, 1), 2) AS size_ratio,
         timestampdiff(SECOND, a.end_time, e.file_time) AS seconds_query_to_file,
         row_number() OVER (PARTITION BY a.statement_id ORDER BY e.file_time) AS rn
  FROM a JOIN silver_endpoint_files e
    ON e.device_id = a.device_id AND e.user_email = a.user_email
   AND e.file_time BETWEEN a.end_time AND a.end_time + INTERVAL 15 MINUTES
   AND (   (lower(a.client_application) LIKE 'dbeaver%' AND e.process_name LIKE 'dbeaver%')
        OR (a.client_application LIKE 'Microsoft Excel%' AND e.process_name = 'excel.exe')
        OR (a.client_application = 'Power BI' AND e.process_name = 'pbidesktop.exe'))
   AND e.size_bytes BETWEEN a.read_bytes * 0.2 AND a.read_bytes * 3
),
u AS (
  SELECT f.statement_id, d.event_id AS upload_event_id, d.upload_time, d.app, d.instance_type, d.destination,
         d.destination_account, d.bytes AS upload_bytes, d.action, d.outcome, d.policy, d.dlp_profile, d.is_unapproved_destination,
         timestampdiff(SECOND, f.file_time, d.upload_time) AS seconds_file_to_upload,
         row_number() OVER (PARTITION BY f.statement_id ORDER BY d.upload_time) AS rn
  FROM f JOIN silver_dlp_events d
    ON d.sha256 = f.sha256 AND d.upload_time BETWEEN f.file_time AND f.file_time + INTERVAL 2 HOURS
  WHERE f.rn = 1
)
SELECT concat('CH-', substr(a.statement_id, 1, 18)) AS chain_id,
  a.statement_id, a.employee_id, a.full_name, a.department, a.role, a.user_email, a.asset_full_name, a.sensitivity,
  a.regulation, a.access_date, a.start_time AS query_start, a.end_time AS query_end, a.start_local AS query_local,
  a.produced_rows, a.read_bytes, a.client_application, a.device_id, a.device_hostname, a.device_assigned_to_user,
  a.exception_ticket, a.has_approved_workflow,
  f.file_event_id, f.file_time, f.process_name, f.file_path, f.file_name, f.sha256, f.size_bytes, f.size_ratio, f.seconds_query_to_file,
  u.upload_event_id, u.upload_time, u.app AS upload_app, u.instance_type, u.destination, u.destination_account,
  u.upload_bytes, u.action AS dlp_action, u.outcome AS upload_outcome, u.dlp_profile, u.seconds_file_to_upload,
  coalesce(u.is_unapproved_destination, false) AS is_unauthorized_destination,
  CASE WHEN u.upload_event_id IS NOT NULL AND u.is_unapproved_destination THEN 'uploaded_unauthorized'
       WHEN u.upload_event_id IS NOT NULL THEN 'uploaded_approved'
       ELSE 'materialized_only' END AS chain_stage
FROM a
JOIN f ON a.statement_id = f.statement_id AND f.rn = 1
LEFT JOIN u ON a.statement_id = u.statement_id AND u.rn = 1;

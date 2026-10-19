-- Behavioral feature vector per employee-day for the anomaly model
CREATE OR REFRESH MATERIALIZED VIEW gold_user_daily_features
COMMENT 'Employee-day features across identity, Databricks data access, endpoint and DLP for ML anomaly detection'
TBLPROPERTIES ('quality' = 'gold')
AS WITH days AS (
  SELECT employee_id, to_date(signin_local) AS activity_date,
         count(*) AS signins, count_if(NOT device_assigned_to_user) AS unassigned_device_signins,
         count_if(is_new_device_for_user) AS new_device_signins,
         count_if(hour(signin_local) < 7 OR hour(signin_local) >= 20) AS off_hours_signins
  FROM silver_identity_sessions GROUP BY ALL
),
acc AS (
  SELECT employee_id, access_date AS activity_date,
         count(*) AS sensitive_statements, sum(produced_rows) AS rows_returned,
         max(sensitivity_rank) AS max_sensitivity_rank, count_if(is_off_hours AND sensitivity_rank >= 2) AS off_hours_sensitive_statements,
         count(DISTINCT client_application) AS client_apps
  FROM silver_sensitive_access GROUP BY ALL
),
an AS (
  SELECT employee_id, access_date AS activity_date, max(ratio_vs_self) AS max_ratio_vs_self, max(ratio_vs_peers) AS max_ratio_vs_peers,
         count_if(is_first_access_to_asset AND sensitivity_rank >= 3) AS first_access_restricted
  FROM gold_access_anomalies GROUP BY ALL
),
files AS (
  SELECT e.employee_id, to_date(from_utc_timestamp(f.file_time, e.timezone)) AS activity_date, count(*) AS files_created, sum(f.size_bytes) AS file_bytes
  FROM silver_endpoint_files f JOIN silver_employees e ON f.user_email = e.email GROUP BY ALL
),
up AS (
  SELECT e.employee_id, to_date(from_utc_timestamp(d.upload_time, e.timezone)) AS activity_date,
         count_if(d.is_unapproved_destination) AS personal_uploads,
         coalesce(sum(CASE WHEN d.is_unapproved_destination THEN d.bytes END), 0) AS personal_upload_bytes,
         count_if(d.dlp_profile IS NOT NULL AND d.is_unapproved_destination) AS sensitive_personal_uploads
  FROM silver_dlp_events d JOIN silver_employees e ON d.user_email = e.email GROUP BY ALL
),
ch AS (
  SELECT employee_id, access_date AS activity_date, count_if(chain_stage = 'uploaded_unauthorized') AS unauthorized_chains
  FROM gold_exfil_chains GROUP BY ALL
)
SELECT concat(d.employee_id, '|', d.activity_date) AS feature_id, d.employee_id, e.full_name, e.department, e.role, d.activity_date,
  d.signins, d.unassigned_device_signins, d.new_device_signins, d.off_hours_signins,
  coalesce(a.sensitive_statements, 0) AS sensitive_statements, coalesce(a.rows_returned, 0) AS rows_returned,
  coalesce(a.max_sensitivity_rank, 0) AS max_sensitivity_rank, coalesce(a.off_hours_sensitive_statements, 0) AS off_hours_sensitive_statements,
  coalesce(a.client_apps, 0) AS client_apps,
  coalesce(n.max_ratio_vs_self, 0) AS max_ratio_vs_self, coalesce(n.max_ratio_vs_peers, 0) AS max_ratio_vs_peers,
  coalesce(n.first_access_restricted, 0) AS first_access_restricted,
  coalesce(f.files_created, 0) AS files_created, coalesce(f.file_bytes, 0) AS file_bytes,
  coalesce(u.personal_uploads, 0) AS personal_uploads, coalesce(u.personal_upload_bytes, 0) AS personal_upload_bytes,
  coalesce(u.sensitive_personal_uploads, 0) AS sensitive_personal_uploads, coalesce(c.unauthorized_chains, 0) AS unauthorized_chains
FROM days d
JOIN silver_employees e USING (employee_id)
LEFT JOIN acc a USING (employee_id, activity_date)
LEFT JOIN an n USING (employee_id, activity_date)
LEFT JOIN files f USING (employee_id, activity_date)
LEFT JOIN up u USING (employee_id, activity_date)
LEFT JOIN ch c USING (employee_id, activity_date);

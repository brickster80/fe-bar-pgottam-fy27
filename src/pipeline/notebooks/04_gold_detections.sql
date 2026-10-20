-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Gold - baselines, movement chains and incidents (Q2-Q4)
-- MAGIC
-- MAGIC **Q2** - was the access unusual for the employee and their peers? **Q3** - did the data move to an unauthorized destination? **Q4** - what evidence supports the assessment?
-- MAGIC
-- MAGIC This notebook is a Lakeflow pipeline source; run it through pipeline `febar-e2e-access-movement`.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Q2 - Unusual vs self and peers

-- COMMAND ----------

-- Q2: Was the access unusual for that employee and their peers?  (employee x asset x day)
CREATE OR REFRESH MATERIALIZED VIEW gold_access_anomalies
COMMENT 'Per employee x governed asset x day: volume vs own baseline and vs department peers, first-time access, off-hours, new device'
TBLPROPERTIES ('quality' = 'gold')
AS WITH d AS (
  SELECT employee_id, full_name, department, role, asset_full_name, sensitivity, sensitivity_rank, access_date,
         count(*) AS statements, sum(produced_rows) AS rows_returned, max(produced_rows) AS max_rows_single_query,
         count_if(is_off_hours) AS off_hours_statements, bool_or(is_new_device_session) AS new_device_session,
         bool_or(NOT device_assigned_to_user) AS unassigned_device, bool_or(is_close_period) AS close_period,
         bool_or(has_approved_workflow) AS has_approved_workflow, max(exception_ticket) AS exception_ticket,
         array_sort(collect_set(client_application)) AS client_apps, min(start_local) AS first_access_local
  FROM silver_sensitive_access WHERE execution_status = 'FINISHED'
  GROUP BY ALL
),
user_daily AS (   -- employee's normal total daily volume across governed financial assets
  SELECT employee_id, access_date, sum(rows_returned) AS user_rows_day FROM d WHERE sensitivity_rank >= 2 GROUP BY ALL
),
user_base AS (
  SELECT employee_id, percentile_approx(user_rows_day, 0.5) AS user_median_daily_rows,
         percentile_approx(user_rows_day, 0.95) AS user_p95_daily_rows
  FROM user_daily GROUP BY employee_id
),
peer AS (         -- department peers on the same asset
  SELECT department, asset_full_name, percentile_approx(rows_returned, 0.5) AS peer_median_daily_rows,
         percentile_approx(rows_returned, 0.95) AS peer_p95_daily_rows, count(DISTINCT employee_id) AS peers_using_asset
  FROM d GROUP BY ALL
),
dept_size AS (SELECT department, count(*) AS dept_headcount FROM silver_employees GROUP BY department),
firsts AS (SELECT employee_id, asset_full_name, min(access_date) AS first_access_date FROM d GROUP BY ALL)
SELECT concat(d.employee_id, '|', d.asset_full_name, '|', d.access_date) AS anomaly_id, d.*,
  ub.user_median_daily_rows, ub.user_p95_daily_rows,
  p.peer_median_daily_rows, p.peer_p95_daily_rows, p.peers_using_asset, ds.dept_headcount,
  round(p.peers_using_asset / ds.dept_headcount, 3) AS peer_adoption_rate,
  CASE WHEN ub.user_median_daily_rows > 0 THEN round(d.rows_returned / ub.user_median_daily_rows, 1) END AS ratio_vs_self,
  round(d.rows_returned / greatest(p.peer_median_daily_rows, 1), 1) AS ratio_vs_peers,
  (f.first_access_date = d.access_date AND d.access_date >= DATE'2026-07-15') AS is_first_access_to_asset
FROM d
LEFT JOIN user_base ub USING (employee_id)
JOIN peer p USING (department, asset_full_name)
JOIN dept_size ds USING (department)
JOIN firsts f USING (employee_id, asset_full_name);

-- COMMAND ----------

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

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Q3 - Access -> file -> destination

-- COMMAND ----------

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

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Q4 - Incidents and evidence timeline

-- COMMAND ----------

-- One candidate incident per employee x day, fusing identity, data-access, file and destination evidence
CREATE OR REFRESH MATERIALIZED VIEW gold_incidents
COMMENT 'Fusion incidents (employee x day): rules risk score, chain stage, ATT&CK techniques, and indicators for the two competing hypotheses'
TBLPROPERTIES ('quality' = 'gold')
AS WITH an AS (
  SELECT employee_id, access_date,
    max(sensitivity_rank) AS max_sensitivity_rank,
    max(ratio_vs_self) AS max_ratio_vs_self, max(ratio_vs_peers) AS max_ratio_vs_peers,
    max(rows_returned) AS max_rows_day_asset, max(user_median_daily_rows) AS user_median_daily_rows,
    max(peer_median_daily_rows) FILTER (WHERE sensitivity_rank >= 3) AS peer_median_restricted,
    bool_or(is_first_access_to_asset AND sensitivity_rank >= 3) AS first_access_restricted,
    bool_or(off_hours_statements > 0 AND sensitivity_rank >= 2) AS off_hours_sensitive,
    bool_or(new_device_session) AS new_device_session, bool_or(unassigned_device) AS unassigned_device,
    bool_or(close_period) AS close_period, bool_or(has_approved_workflow AND sensitivity_rank >= 3) AS restricted_workflow_ok,
    max(exception_ticket) AS exception_ticket,
    max_by(asset_full_name, sensitivity_rank * 1e9 + rows_returned) AS primary_asset
  FROM gold_access_anomalies GROUP BY ALL
),
ch AS (
  SELECT employee_id, access_date,
    max_by(chain_id, CASE chain_stage WHEN 'uploaded_unauthorized' THEN 3 WHEN 'uploaded_approved' THEN 2 ELSE 1 END * 1e12 + produced_rows) AS chain_id,
    max(CASE chain_stage WHEN 'uploaded_unauthorized' THEN 3 WHEN 'uploaded_approved' THEN 2 ELSE 1 END) AS chain_rank
  FROM gold_exfil_chains GROUP BY ALL
),
dlp AS (  -- personal-destination uploads that are NOT linked to any sensitive access
  SELECT e.employee_id, to_date(from_utc_timestamp(d.upload_time, e.timezone)) AS access_date,
         count(*) AS unlinked_personal_uploads, sum(d.bytes) AS unlinked_personal_bytes, max(d.upload_time) AS last_personal_upload,
         max(d.destination) AS personal_destination
  FROM silver_dlp_events d JOIN silver_employees e ON d.user_email = e.email
  LEFT JOIN gold_exfil_chains c ON c.upload_event_id = d.event_id
  WHERE d.is_unapproved_destination AND c.chain_id IS NULL
  GROUP BY ALL
),
apps AS (
  SELECT employee_id, access_date, collect_set(client_application) AS apps_today FROM silver_sensitive_access GROUP BY ALL
),
app_base AS (
  SELECT employee_id, client_application, count(DISTINCT access_date) AS days_used FROM silver_sensitive_access GROUP BY ALL
),
k AS (
  SELECT coalesce(an.employee_id, dlp.employee_id) AS employee_id, coalesce(an.access_date, dlp.access_date) AS incident_date,
         an.* EXCEPT (employee_id, access_date), ch.chain_id, ch.chain_rank,
         dlp.unlinked_personal_uploads, dlp.unlinked_personal_bytes, dlp.personal_destination
  FROM an
  LEFT JOIN ch USING (employee_id, access_date)
  FULL OUTER JOIN dlp ON an.employee_id = dlp.employee_id AND an.access_date = dlp.access_date
),
c AS (
  SELECT k.*, x.* EXCEPT (employee_id, access_date, chain_id, sensitivity, regulation, full_name, department, role, user_email, exception_ticket, has_approved_workflow),
         x.sensitivity AS chain_sensitivity, x.regulation AS chain_regulation,
         e.full_name, e.department, e.role, e.email, e.timezone, e.manager_id,
         -- client app used in the chain but on <= 1 other day in the baseline
         (x.client_application IS NOT NULL AND coalesce(ab.days_used, 0) <= 1) AS rare_client_app
  FROM k
  JOIN silver_employees e USING (employee_id)
  LEFT JOIN gold_exfil_chains x ON x.chain_id = k.chain_id
  LEFT JOIN app_base ab ON ab.employee_id = k.employee_id AND ab.client_application = x.client_application
  WHERE coalesce(k.chain_rank, 0) = 3                                                    -- data reached an unauthorized destination
     OR (coalesce(k.chain_rank, 0) >= 1 AND coalesce(k.max_sensitivity_rank, 0) >= 3
         AND greatest(coalesce(k.max_ratio_vs_self, 0), coalesce(k.max_ratio_vs_peers, 0)) >= 5)                                         -- restricted data, unusual volume, left the warehouse
     OR (coalesce(k.max_ratio_vs_self, 0) >= 10 AND coalesce(k.max_sensitivity_rank, 0) >= 3)
     OR (coalesce(k.first_access_restricted, false) AND coalesce(k.off_hours_sensitive, false))
     OR coalesce(k.unlinked_personal_bytes, 0) >= 100000000
),
scored AS (
  SELECT c.*,
    greatest(0, least(100,
        CASE WHEN coalesce(unassigned_device, false) THEN 15 ELSE 0 END
      + CASE WHEN coalesce(off_hours_sensitive, false) THEN 10 ELSE 0 END
      + CASE WHEN coalesce(first_access_restricted, false) THEN 15 ELSE 0 END
      + CASE WHEN coalesce(max_ratio_vs_self, 0) >= 50 THEN 25 WHEN coalesce(max_ratio_vs_self, 0) >= 10 THEN 15 ELSE 0 END
      + CASE WHEN coalesce(max_ratio_vs_peers, 0) >= 20 THEN 10 ELSE 0 END
      + CASE WHEN coalesce(chain_rank, 0) >= 1 THEN 10 ELSE 0 END
      + CASE WHEN chain_rank = 3 THEN 30 ELSE 0 END
      + CASE WHEN coalesce(rare_client_app, false) THEN 5 ELSE 0 END
      + CASE WHEN coalesce(unlinked_personal_bytes, 0) >= 100000000 THEN 10 ELSE 0 END
      - CASE WHEN exception_ticket IS NOT NULL THEN 40 ELSE 0 END
      - CASE WHEN coalesce(close_period, false) THEN 5 ELSE 0 END)) AS rules_risk_score
  FROM c
)
SELECT
  concat('INC-', date_format(incident_date, 'yyyyMMdd'), '-', employee_id) AS incident_id,
  employee_id, full_name, email, department, role, manager_id, timezone, incident_date,
  primary_asset, max_sensitivity_rank, max_rows_day_asset, user_median_daily_rows, peer_median_restricted,
  max_ratio_vs_self, max_ratio_vs_peers, coalesce(first_access_restricted, false) AS first_access_restricted,
  coalesce(off_hours_sensitive, false) AS off_hours_sensitive, coalesce(new_device_session, false) AS new_device_session,
  coalesce(unassigned_device, false) AS unassigned_device, coalesce(close_period, false) AS close_period,
  coalesce(restricted_workflow_ok, false) AS restricted_workflow_ok, exception_ticket,
  chain_id, statement_id, query_local, produced_rows, client_application, device_id, device_hostname,
  file_event_id, file_time, process_name, file_name, sha256, size_bytes, upload_event_id, upload_time, upload_app,
  instance_type, destination, destination_account, upload_bytes, dlp_profile, dlp_action,
  coalesce(chain_stage, CASE WHEN unlinked_personal_bytes IS NOT NULL THEN 'dlp_only_no_sensitive_lineage' ELSE 'access_only' END) AS chain_stage,
  coalesce(is_unauthorized_destination, false) AS is_unauthorized_destination,
  unlinked_personal_uploads, unlinked_personal_bytes, personal_destination, rare_client_app,
  rules_risk_score,
  CASE WHEN exception_ticket IS NOT NULL THEN 'Explained by exception'
       WHEN rules_risk_score >= 70 THEN 'Escalate'
       WHEN rules_risk_score >= 40 THEN 'Review'
       ELSE 'Low' END AS triage_recommendation,
  filter(array(
    CASE WHEN unassigned_device OR off_hours_sensitive THEN 'T1078 Valid Accounts' END,
    CASE WHEN coalesce(max_ratio_vs_self, 0) >= 10 OR first_access_restricted THEN 'T1213 Data from Information Repositories' END,
    CASE WHEN file_event_id IS NOT NULL THEN 'T1074.001 Local Data Staging' END,
    CASE WHEN is_unauthorized_destination THEN 'T1567.002 Exfiltration to Cloud Storage' END), x -> x IS NOT NULL) AS attack_techniques,
  filter(array(
    CASE WHEN unassigned_device THEN concat('Signed in from ', coalesce(device_hostname, 'a device'), ', never associated with this employee') END,
    CASE WHEN rare_client_app THEN concat(client_application, ' not used by this employee in the baseline') END,
    CASE WHEN off_hours_sensitive THEN 'Sensitive access outside business hours' END,
    CASE WHEN first_access_restricted THEN 'First-ever access to this restricted asset' END), x -> x IS NOT NULL) AS compromise_indicators,
  filter(array(
    CASE WHEN statement_id IS NOT NULL THEN 'Employee holds a legitimate read grant on the asset' END,
    CASE WHEN device_hostname LIKE 'LOANER%' THEN 'Device is a corporate loaner - obtaining it requires physical access to the office pool' END,
    CASE WHEN chain_stage IS NOT NULL THEN 'Sign-in passed MFA with the employee''s enrolled factor' END,
    CASE WHEN instance_type = 'personal' THEN 'Destination is a personal (non-corporate) cloud account' END), x -> x IS NOT NULL) AS misuse_indicators,
  filter(array(
    CASE WHEN exception_ticket IS NOT NULL THEN concat('Approved exception ', exception_ticket, ' covers this access') END,
    CASE WHEN instance_type = 'corporate' THEN 'Upload went to the approved corporate tenant' END,
    CASE WHEN close_period THEN 'Month-end close period (higher volumes expected)' END,
    CASE WHEN chain_stage IS NULL AND unlinked_personal_bytes IS NOT NULL THEN 'Personal upload has no lineage to any governed financial asset' END), x -> x IS NOT NULL) AS mitigating_factors
FROM scored;

-- COMMAND ----------

-- Q4: What evidence supports the threat assessment?  Ordered, source-attributed evidence per incident
CREATE OR REFRESH MATERIALIZED VIEW gold_incident_timeline
COMMENT 'Evidence timeline per incident: local time, source system, observation, why it matters, evidence reference'
TBLPROPERTIES ('quality' = 'gold')
AS WITH i AS (SELECT * FROM gold_incidents),
first_touch AS (   -- first statement against the primary asset that day
  SELECT i.incident_id, min_by(s.statement_id, s.start_time) AS statement_id, min(s.start_time) AS t,
         min_by(s.produced_rows, s.start_time) AS rows_first
  FROM i JOIN silver_sensitive_access s
    ON s.employee_id = i.employee_id AND s.access_date = i.incident_date AND s.asset_full_name = i.primary_asset
  GROUP BY i.incident_id
),
signin AS (
  SELECT i.incident_id, s.signin_id, s.signin_time, s.device_hostname, s.risk_level, s.network, s.factor, s.device_assigned_to_user
  FROM i JOIN silver_sensitive_access a ON a.statement_id = i.statement_id
  JOIN silver_identity_sessions s ON s.signin_id = a.signin_id
),
ev AS (
  SELECT s.incident_id, s.signin_time AS event_time, 'Identity provider (Okta)' AS source,
    concat(i.full_name, ' signs in from ', s.device_hostname, ' via ', s.factor, ' (', s.network, ' network, IdP risk ', s.risk_level, ')') AS observation,
    CASE WHEN NOT s.device_assigned_to_user THEN 'Device not previously associated with the account: adds identity risk, but does not establish compromise.'
         ELSE 'Known, assigned device: no identity anomaly.' END AS why_it_matters,
    s.signin_id AS evidence_ref, 1 AS ord
  FROM signin s JOIN i USING (incident_id)
  UNION ALL
  SELECT f.incident_id, f.t, 'Databricks audit + lineage',
    concat('First query of the day against ', i.primary_asset, ' (', f.rows_first, ' rows)'),
    CASE WHEN i.first_access_restricted THEN 'First access to this restricted asset in the baseline period: a sensitive-data access anomaly.'
         ELSE 'Asset is used by this employee in the baseline.' END,
    f.statement_id, 2
  FROM first_touch f JOIN i USING (incident_id)
  WHERE f.statement_id <> coalesce(i.statement_id, '')
  UNION ALL
  SELECT incident_id, to_utc_timestamp(query_local, timezone), 'Databricks query history',
    concat('Query returns ', format_number(produced_rows, 0), ' rows from ', primary_asset, ' via ', client_application,
           ' vs a normal daily volume of about ', format_number(user_median_daily_rows, 0), ' rows'),
    'Unusual collection volume relative to the employee''s own baseline; not proof of export.',
    statement_id, 3
  FROM i WHERE statement_id IS NOT NULL
  UNION ALL
  SELECT incident_id, file_time, 'Endpoint (CrowdStrike EDR)',
    concat(process_name, ' creates ', file_name, ' (', round(size_bytes / 1e6, 1), ' MB) on ', device_hostname),
    'Local materialization: the creating process matches the query client and the file size matches the result set.',
    file_event_id, 4
  FROM i WHERE file_event_id IS NOT NULL
  UNION ALL
  SELECT incident_id, upload_time, 'DLP / CASB (Netskope)',
    concat('Upload of ', file_name, ' (same SHA-256) to ', upload_app, ' ', instance_type, ' account ', destination_account,
           ', DLP profile: ', coalesce(dlp_profile, 'none'), ', action: ', dlp_action),
    CASE WHEN is_unauthorized_destination THEN 'Data crossed an unauthorized boundary: personal cloud account, not the corporate tenant.'
         ELSE 'Destination is the approved corporate tenant.' END,
    upload_event_id, 5
  FROM i WHERE upload_event_id IS NOT NULL
  UNION ALL
  SELECT incident_id, coalesce(upload_time, file_time, to_utc_timestamp(query_local, timezone)) + INTERVAL 2 MINUTES, 'Correlation (Databricks)',
    concat('Correlation produces ', incident_id, ': ', chain_stage, ', rules risk ', rules_risk_score, ', ', array_join(attack_techniques, ', ')),
    'Separate identity, data-access, file and upload alerts become one explainable investigation.',
    incident_id, 6
  FROM i WHERE statement_id IS NOT NULL
)
SELECT ev.incident_id, ev.ord AS step, ev.event_time AS event_time_utc,
  from_utc_timestamp(ev.event_time, i.timezone) AS event_time_local,
  date_format(from_utc_timestamp(ev.event_time, i.timezone), 'HH:mm') AS local_hhmm,
  ev.source, ev.observation, ev.why_it_matters, ev.evidence_ref
FROM ev JOIN gold_incidents i USING (incident_id);

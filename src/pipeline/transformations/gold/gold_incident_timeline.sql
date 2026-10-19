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

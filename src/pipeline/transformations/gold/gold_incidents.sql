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

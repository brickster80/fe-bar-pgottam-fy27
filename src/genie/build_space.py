"""Builds genie_space.json for the 'Authorized access, unauthorized movement' Genie space."""
import json
FQ = "capmarkets_stg.febar_e2e"
tables = ["gold_incident_risk", "gold_incident_assessments", "gold_incident_timeline", "gold_exfil_chains",
          "gold_access_anomalies", "gold_user_day_anomaly", "silver_sensitive_access", "silver_identity_sessions",
          "silver_dlp_events", "silver_employees", "silver_asset_registry", "silver_exceptions"]
samples = [
    "Who accessed sensitive financial data in the last two weeks of September?",
    "Which restricted-data accesses were most unusual for the employee and their department peers?",
    "Did any sensitive data move to an unauthorized destination?",
    "What evidence supports the threat assessment for the highest-priority incident?",
    "Who accessed vendor bank accounts for the first time, and from which device?",
    "Which large extracts were explained by an approved exception ticket?",
]
sqls = [
    ("Who accessed sensitive financial data?",
     f"""SELECT full_name, department, role, asset_full_name, sensitivity, count(*) AS queries,
       sum(produced_rows) AS rows_returned, count_if(is_off_hours) AS off_hours_queries,
       count_if(NOT device_assigned_to_user) AS queries_from_unassigned_device
FROM {FQ}.silver_sensitive_access
WHERE sensitivity_rank >= 3 AND access_date >= DATE'2026-09-16'
GROUP BY ALL ORDER BY rows_returned DESC LIMIT 25"""),
    ("Was the access unusual for the employee and their peers?",
     f"""SELECT full_name, department, role, asset_full_name, access_date, rows_returned, user_median_daily_rows, ratio_vs_self,
       peer_median_daily_rows, ratio_vs_peers, peers_using_asset, dept_headcount, is_first_access_to_asset,
       off_hours_statements, unassigned_device
FROM {FQ}.gold_access_anomalies
WHERE sensitivity_rank >= 3
ORDER BY greatest(coalesce(ratio_vs_self, 0), coalesce(ratio_vs_peers, 0)) DESC LIMIT 10"""),
    ("How did sensitive data move, by chain stage?",
     f"""SELECT chain_stage, count(*) AS chains, count(DISTINCT employee_id) AS employees,
       sum(produced_rows) AS rows_moved, collect_set(destination) AS destinations
FROM {FQ}.gold_exfil_chains GROUP BY chain_stage
ORDER BY CASE chain_stage WHEN 'uploaded_unauthorized' THEN 1 WHEN 'uploaded_approved' THEN 2 ELSE 3 END"""),
    ("Did data move to an unauthorized destination?",
     f"""SELECT full_name, department, asset_full_name, query_local, produced_rows, client_application, device_hostname,
       file_name, round(size_bytes / 1e6, 1) AS file_mb, upload_app, instance_type, destination_account, dlp_profile, upload_time
FROM {FQ}.gold_exfil_chains
WHERE chain_stage = 'uploaded_unauthorized'"""),
    ("What evidence supports the threat assessment?",
     f"""SELECT t.local_hhmm, t.source, t.observation, t.why_it_matters, t.evidence_ref
FROM {FQ}.gold_incident_timeline t
WHERE t.incident_id = (SELECT incident_id FROM {FQ}.gold_incident_risk ORDER BY priority, fused_risk DESC LIMIT 1)
ORDER BY t.step"""),
    ("Before the incident, had the employee used the incident device, and which devices do they normally use?",
     f"""WITH top AS (SELECT incident_id, employee_id, device_id FROM {FQ}.gold_incident_risk ORDER BY priority, fused_risk DESC LIMIT 1),
inc AS (SELECT min(s.signin_time) AS incident_signin FROM {FQ}.silver_identity_sessions s JOIN top t
        ON s.employee_id = t.employee_id AND s.device_id = t.device_id)
SELECT s.full_name, s.department, s.device_hostname, s.device_type, s.device_assigned_to_user,
       count_if(s.signin_time < inc.incident_signin) AS signins_before_incident,
       min(s.signin_local) AS first_seen_local, max(s.signin_local) AS last_seen_local
FROM {FQ}.silver_identity_sessions s JOIN top t ON s.employee_id = t.employee_id CROSS JOIN inc
GROUP BY ALL ORDER BY signins_before_incident DESC"""),
    ("Was the destination account from the incident used by anyone else?",
     f"""WITH top AS (SELECT incident_id, employee_id FROM {FQ}.gold_incident_risk ORDER BY priority, fused_risk DESC LIMIT 1),
acct AS (SELECT DISTINCT c.destination_account FROM {FQ}.gold_exfil_chains c JOIN top t ON c.employee_id = t.employee_id
         WHERE c.chain_stage = 'uploaded_unauthorized')
SELECT a.destination_account, count(DISTINCT d.user_email) AS employees_using_account, collect_set(d.user_email) AS users,
       count(*) AS uploads, min(d.upload_time) AS first_upload, max(d.upload_time) AS last_upload
FROM acct a LEFT JOIN {FQ}.silver_dlp_events d ON d.destination_account = a.destination_account
GROUP BY a.destination_account"""),
    ("Which large extracts were explained by an exception ticket?",
     f"""SELECT r.full_name, r.department, r.primary_asset, r.produced_rows, r.exception_ticket, x.justification, x.approver,
       r.destination, r.priority
FROM {FQ}.gold_incident_risk r JOIN {FQ}.silver_exceptions x ON x.ticket_id = r.exception_ticket"""),
]
instructions = f"""You are the investigation assistant for Halcyon Financial's "Authorized access, unauthorized movement" fusion use case.
You answer four questions: (1) who accessed sensitive financial data, (2) whether it was unusual for the employee and their department peers, (3) whether data moved to an unauthorized destination, (4) what evidence supports the threat assessment.
Data window: 2026-07-01 to 2026-09-30. "Recent", "last two weeks" or "now" means dates >= DATE'2026-09-16'. Do NOT use current_date().
Times: *_local and local_hhmm columns are the employee's local time; *_time / *_utc are UTC. Prefer local time in answers.

GOVERNED ASSETS (asset_full_name): finance_prod.reporting.monthly_summary (confidential, routine reporting), finance_prod.treasury.vendor_bank_accounts (restricted, approved treasury workflows), finance_prod.strategy.acquisition_forecast (highly_restricted, corporate development only). "Sensitive financial data" = sensitivity_rank >= 2; "restricted" = sensitivity_rank >= 3.

TABLE GUIDE
- Q1 who accessed: silver_sensitive_access (one row per statement: employee, asset, rows, client app, device, local time, workflow and exception context).
- Q2 unusual: gold_access_anomalies (employee x asset x day: ratio_vs_self, ratio_vs_peers, is_first_access_to_asset, peers_using_asset) and gold_user_day_anomaly (ML anomaly_score 0-1, top_drivers).
- Q3 moved: gold_exfil_chains (query -> file on same device by client process -> upload of same SHA-256). chain_stage: uploaded_unauthorized | uploaded_approved | materialized_only.
- Q4 evidence: gold_incident_timeline (ordered steps with source, observation, why_it_matters) and gold_incident_assessments (GenAI assessment + leading_hypothesis).
- gold_incident_risk: one row per candidate incident with rules_risk_score, anomaly_score, fused_risk, priority P1-P4, attack_techniques, compromise_indicators, misuse_indicators, mitigating_factors.
- silver_identity_sessions: IdP sign-ins with device assignment (device_assigned_to_user, is_new_device_for_user).
- silver_dlp_events: uploads; is_unapproved_destination = not the corporate tenant.

INVESTIGATION CONVENTIONS
- "Highest-priority" / "top" / "that" incident = gold_incident_risk ORDER BY priority ASC, fused_risk DESC; in follow-ups keep using the incident (incident_id) or employee from the previous answer.
- "Did data move?" questions: summarise gold_exfil_chains by chain_stage first, then list uploaded_unauthorized chains first. Approved corporate uploads are expected business activity, not findings.
- Device history: is_new_device_for_user = true on the incident sign-in means the employee had never used that device before.
- "Before the incident" / "previously" = strictly earlier than the incident's first event (e.g. signin_time < the incident sign-in); never count the incident's own sign-in, query or upload as prior history.
- Separating the hypotheses: compromise is supported by other employees signing in from the same device (silver_identity_sessions by device_hostname) or anomalous sign-in context; misuse is supported by the employee's own managed device and normal sign-in pattern. A personal destination_account seen for only one employee is neither proof of misuse nor of compromise.

RULES
- Never claim the employee is malicious. Present the two hypotheses (insider misuse vs account/device compromise) with their indicators.
- Always answer in English, including follow-up suggestions.
- Always include full_name, department and role when listing employees. Format large numbers with thousands separators."""


def hid(prefix, i): return f"{prefix}{i:031d}"


space = {
    "version": 2,
    "config": {"sample_questions": [{"id": hid(1, i + 1), "question": [q]} for i, q in enumerate(samples)]},
    "data_sources": {"tables": [{"identifier": f"{FQ}.{t}"} for t in sorted(tables)]},
    "instructions": {
        "example_question_sqls": [{"id": hid(2, i + 1), "question": [q], "sql": [l + "\n" for l in s.splitlines()]} for i, (q, s) in enumerate(sqls)],
        "text_instructions": [{"id": hid(3, 1), "content": [l + "\n" for l in instructions.splitlines()]}],
    },
}
json.dump(space, open("genie_space.json", "w"), indent=2)
print("ok")

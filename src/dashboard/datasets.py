"""Dataset SQL for the 'Authorized access, unauthorized movement' AI/BI dashboard (bare table names)."""
DATASETS = {
    "ds_access": ("Q1 Sensitive access (statement level)", """
SELECT statement_id, access_date, department, full_name, role,
       replace(replace(asset_full_name, 'invest_prod.', ''), 'clients_prod.', '') AS asset, sensitivity, sensitivity_rank,
       produced_rows, client_application, is_off_hours,
       CASE WHEN device_assigned_to_user THEN 'Assigned device' ELSE 'Unassigned device' END AS device_context,
       CASE WHEN exception_ticket IS NOT NULL THEN 'Exception ticket' WHEN has_approved_workflow THEN 'Approved workflow' ELSE 'Outside workflow' END AS workflow_context
FROM silver_sensitive_access
WHERE sensitivity_rank >= 2 AND execution_status = 'FINISHED'
"""),
    "ds_anomalies": ("Q2 Access vs self and peers", """
SELECT anomaly_id, access_date, department, full_name, role,
       replace(asset_full_name, 'invest_prod.', '') AS asset, sensitivity, rows_returned, user_median_daily_rows,
       peer_median_daily_rows, ratio_vs_self, ratio_vs_peers, is_first_access_to_asset, unassigned_device,
       CASE WHEN ratio_vs_self >= 10 OR ratio_vs_peers >= 20 THEN 'Unusual' ELSE 'Within baseline' END AS volume_verdict
FROM gold_access_anomalies
WHERE sensitivity_rank >= 2
"""),
    "ds_ml": ("Q2 ML anomaly (employee-day)", """
SELECT feature_id, activity_date AS access_date, department, full_name, role, anomaly_score, is_anomaly,
       round(anomaly_score * 100, 1) AS anomaly_100, array_join(top_drivers, ' | ') AS drivers,
       CASE WHEN is_anomaly THEN 'Anomalous' ELSE 'Normal' END AS ml_label
FROM gold_user_day_anomaly
"""),
    "ds_chains": ("Q3 Access -> file -> destination chains", """
SELECT chain_id, access_date, department, full_name, role, replace(asset_full_name, 'invest_prod.', '') AS asset,
       produced_rows, client_application, device_hostname, file_name, round(size_bytes / 1e6, 1) AS file_mb,
       coalesce(upload_app, 'No upload') AS upload_app, coalesce(instance_type, 'none') AS instance_type,
       coalesce(destination_account, '') AS destination_account, chain_stage,
       CASE chain_stage WHEN 'uploaded_unauthorized' THEN 'Unauthorized destination'
                        WHEN 'uploaded_approved' THEN 'Approved corporate tenant' ELSE 'Local file only' END AS movement
FROM gold_exfil_chains
"""),
    "ds_incidents": ("Q4 Incidents and assessments", """
SELECT r.incident_id, r.incident_date AS access_date, r.department, r.full_name, r.role, r.priority, r.fused_risk,
       r.rules_risk_score, round(coalesce(r.anomaly_score, 0) * 100, 1) AS ml_anomaly_100, r.chain_stage,
       replace(r.primary_asset, 'invest_prod.', '') AS asset, r.produced_rows, r.exception_ticket,
       array_join(r.attack_techniques, ', ') AS attack_techniques,
       array_join(r.compromise_indicators, '; ') AS compromise_indicators,
       array_join(r.misuse_indicators, '; ') AS misuse_indicators,
       array_join(r.mitigating_factors, '; ') AS mitigating_factors,
       coalesce(a.leading_hypothesis, '') AS leading_hypothesis
FROM gold_incident_risk r LEFT JOIN gold_incident_assessments a USING (incident_id)
"""),
    "ds_timeline": ("Q4 Evidence timeline", """
SELECT t.incident_id, concat(t.incident_id, '-', t.step) AS evidence_key, t.step, t.local_hhmm, t.source, t.observation,
       t.why_it_matters, t.evidence_ref, r.full_name, r.department, r.incident_date AS access_date, r.priority
FROM gold_incident_timeline t JOIN gold_incident_risk r USING (incident_id)
"""),
}

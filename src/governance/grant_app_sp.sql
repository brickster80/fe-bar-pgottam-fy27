-- Least-privilege grants for the febar-e2e-console app service principal (e47b15f2-c014-4729-bcb0-759c6bfc3554)
GRANT USE CATALOG ON CATALOG capmarkets_stg TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT USE SCHEMA ON SCHEMA capmarkets_stg.febar_e2e TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.silver_sensitive_access TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.gold_user_day_anomaly TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.gold_exfil_chains TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.gold_incident_risk TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.gold_access_anomalies TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.strategy_acquisition_forecast TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.gov_access_policy TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.v_live_audit_governed TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.v_live_lineage_governed TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT SELECT ON TABLE capmarkets_stg.febar_e2e.v_live_query_evidence TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT EXECUTE ON FUNCTION capmarkets_stg.febar_e2e.mask_bank_number TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;
GRANT EXECUTE ON FUNCTION capmarkets_stg.febar_e2e.filter_forecast TO `e47b15f2-c014-4729-bcb0-759c6bfc3554`;

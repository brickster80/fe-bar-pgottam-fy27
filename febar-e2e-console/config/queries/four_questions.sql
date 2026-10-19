-- The investigation funnel: each question narrows the population
SELECT 1 AS step, 'Q1 Queries against sensitive financial data' AS stage, (SELECT count(*) FROM capmarkets_stg.febar_e2e.silver_sensitive_access WHERE sensitivity_rank >= 2) AS cnt
UNION ALL SELECT 2, 'Q1 Employees who touched restricted assets', (SELECT count(DISTINCT employee_id) FROM capmarkets_stg.febar_e2e.silver_sensitive_access WHERE sensitivity_rank >= 3)
UNION ALL SELECT 3, 'Q2 Employee-days unusual vs self/peers (ML)', (SELECT count(*) FROM capmarkets_stg.febar_e2e.gold_user_day_anomaly WHERE is_anomaly)
UNION ALL SELECT 4, 'Q3 Sensitive results materialized to files', (SELECT count(*) FROM capmarkets_stg.febar_e2e.gold_exfil_chains)
UNION ALL SELECT 5, 'Q3 Files moved to an unauthorized destination', (SELECT count(*) FROM capmarkets_stg.febar_e2e.gold_exfil_chains WHERE chain_stage = 'uploaded_unauthorized')
UNION ALL SELECT 6, 'Q4 P1 incidents with full evidence', (SELECT count(*) FROM capmarkets_stg.febar_e2e.gold_incident_risk WHERE priority = 'P1')
ORDER BY step

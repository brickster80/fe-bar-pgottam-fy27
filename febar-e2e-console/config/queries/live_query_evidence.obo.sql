-- LIVE system.query.history x system.access.table_lineage for the governed stand-ins (runs as the signed-in user)
SELECT date_format(start_time, 'yyyy-MM-dd HH:mm') AS start_time, executed_by, client_application,
       replace(source_table_full_name, 'capmarkets_stg.febar_e2e.', '') AS governed_table, produced_rows, statement_id
FROM capmarkets_stg.febar_e2e.v_live_query_evidence
ORDER BY start_time DESC
LIMIT 15

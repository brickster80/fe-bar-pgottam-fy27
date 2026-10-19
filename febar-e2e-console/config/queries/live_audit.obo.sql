-- LIVE system.access.audit for the governed stand-ins (runs as the signed-in user)
SELECT date_format(event_time, 'yyyy-MM-dd HH:mm') AS event_time, user_email, service_name, action_name,
       replace(table_full_name, 'capmarkets_stg.febar_e2e.', '') AS governed_table, source_ip_address, status_code
FROM capmarkets_stg.febar_e2e.v_live_audit_governed
ORDER BY event_time DESC
LIMIT 15

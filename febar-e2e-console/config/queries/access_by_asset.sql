-- @param start_date DATE
SELECT asset_full_name, sensitivity, sensitivity_rank, department,
       count(*) AS queries, count(DISTINCT employee_id) AS employees, sum(produced_rows) AS rows_returned,
       count_if(is_off_hours) AS off_hours_queries, count_if(NOT device_assigned_to_user) AS unassigned_device_queries,
       count_if(NOT has_approved_workflow) AS outside_workflow_queries
FROM capmarkets_stg.febar_e2e.silver_sensitive_access
WHERE access_date >= :start_date AND sensitivity_rank >= 2 AND execution_status = 'FINISHED'
GROUP BY ALL
ORDER BY sensitivity_rank DESC, rows_returned DESC

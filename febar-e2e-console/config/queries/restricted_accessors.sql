-- @param start_date DATE
-- Who touched restricted assets (unpublished research, pending block orders), with entitlement and baseline context
SELECT a.employee_id, a.full_name, a.department, a.role, a.asset_full_name,
       sum(a.rows_returned) AS rows_returned, max(a.ratio_vs_self) AS max_ratio_vs_self, max(a.ratio_vs_peers) AS max_ratio_vs_peers,
       bool_or(a.is_first_access_to_asset) AS first_access, bool_or(a.unassigned_device) AS unassigned_device,
       sum(a.off_hours_statements) AS off_hours_queries, bool_or(a.has_approved_workflow) AS approved_workflow,
       max(a.exception_ticket) AS exception_ticket, max(a.peers_using_asset) AS peers_using_asset, max(a.dept_headcount) AS dept_headcount
FROM capmarkets_stg.febar_e2e.gold_access_anomalies a
WHERE a.access_date >= :start_date AND a.sensitivity_rank >= 3
GROUP BY ALL
ORDER BY max_ratio_vs_self DESC NULLS LAST
LIMIT 20

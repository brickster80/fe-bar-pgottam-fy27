-- Q2: Was the access unusual for that employee and their peers?  (employee x asset x day)
CREATE OR REFRESH MATERIALIZED VIEW gold_access_anomalies
COMMENT 'Per employee x governed asset x day: volume vs own baseline and vs department peers, first-time access, off-hours, new device'
TBLPROPERTIES ('quality' = 'gold')
AS WITH d AS (
  SELECT employee_id, full_name, department, role, asset_full_name, sensitivity, sensitivity_rank, access_date,
         count(*) AS statements, sum(produced_rows) AS rows_returned, max(produced_rows) AS max_rows_single_query,
         count_if(is_off_hours) AS off_hours_statements, bool_or(is_new_device_session) AS new_device_session,
         bool_or(NOT device_assigned_to_user) AS unassigned_device, bool_or(is_close_period) AS close_period,
         bool_or(has_approved_workflow) AS has_approved_workflow, max(exception_ticket) AS exception_ticket,
         array_sort(collect_set(client_application)) AS client_apps, min(start_local) AS first_access_local
  FROM silver_sensitive_access WHERE execution_status = 'FINISHED'
  GROUP BY ALL
),
user_daily AS (   -- employee's normal total daily volume across governed financial assets
  SELECT employee_id, access_date, sum(rows_returned) AS user_rows_day FROM d WHERE sensitivity_rank >= 2 GROUP BY ALL
),
user_base AS (
  SELECT employee_id, percentile_approx(user_rows_day, 0.5) AS user_median_daily_rows,
         percentile_approx(user_rows_day, 0.95) AS user_p95_daily_rows
  FROM user_daily GROUP BY employee_id
),
peer AS (         -- department peers on the same asset
  SELECT department, asset_full_name, percentile_approx(rows_returned, 0.5) AS peer_median_daily_rows,
         percentile_approx(rows_returned, 0.95) AS peer_p95_daily_rows, count(DISTINCT employee_id) AS peers_using_asset
  FROM d GROUP BY ALL
),
dept_size AS (SELECT department, count(*) AS dept_headcount FROM silver_employees GROUP BY department),
firsts AS (SELECT employee_id, asset_full_name, min(access_date) AS first_access_date FROM d GROUP BY ALL)
SELECT concat(d.employee_id, '|', d.asset_full_name, '|', d.access_date) AS anomaly_id, d.*,
  ub.user_median_daily_rows, ub.user_p95_daily_rows,
  p.peer_median_daily_rows, p.peer_p95_daily_rows, p.peers_using_asset, ds.dept_headcount,
  round(p.peers_using_asset / ds.dept_headcount, 3) AS peer_adoption_rate,
  CASE WHEN ub.user_median_daily_rows > 0 THEN round(d.rows_returned / ub.user_median_daily_rows, 1) END AS ratio_vs_self,
  round(d.rows_returned / greatest(p.peer_median_daily_rows, 1), 1) AS ratio_vs_peers,
  (f.first_access_date = d.access_date AND d.access_date >= DATE'2026-07-15') AS is_first_access_to_asset
FROM d
LEFT JOIN user_base ub USING (employee_id)
JOIN peer p USING (department, asset_full_name)
JOIN dept_size ds USING (department)
JOIN firsts f USING (employee_id, asset_full_name);

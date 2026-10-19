-- Runs AS THE SIGNED-IN USER: UC row filter decides whether any acquisition forecast rows are visible
SELECT count(*) AS visible_rows, count(DISTINCT project_code) AS visible_projects
FROM capmarkets_stg.febar_e2e.strategy_acquisition_forecast

CREATE OR REFRESH MATERIALIZED VIEW silver_workflows
COMMENT 'Approved workflows: which departments may use which governed asset, and under what conditions'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT workflow_id, workflow_name, asset_full_name, split(approved_departments, ';') AS approved_departments, conditions
FROM bronze_workflows
QUALIFY row_number() OVER (PARTITION BY workflow_id ORDER BY _ingested_at DESC) = 1;

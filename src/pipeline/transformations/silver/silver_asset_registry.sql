CREATE OR REFRESH MATERIALIZED VIEW silver_asset_registry
COMMENT 'Governed financial assets: sensitivity, expected use, regulation, departments granted access, physical UC table'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT asset_full_name, physical_table, sensitivity, cast(sensitivity_rank AS INT) AS sensitivity_rank, content,
  expected_use, regulation, split(granted_departments, ';') AS granted_departments
FROM bronze_asset_registry
QUALIFY row_number() OVER (PARTITION BY asset_full_name ORDER BY _ingested_at DESC) = 1;

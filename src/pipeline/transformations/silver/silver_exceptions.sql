CREATE OR REFRESH MATERIALIZED VIEW silver_exceptions
COMMENT 'Approved access exception tickets'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT ticket_id, employee_id, asset_full_name, justification, cast(valid_from AS DATE) AS valid_from,
  cast(valid_to AS DATE) AS valid_to, status, approver
FROM bronze_exceptions
QUALIFY row_number() OVER (PARTITION BY ticket_id ORDER BY _ingested_at DESC) = 1;

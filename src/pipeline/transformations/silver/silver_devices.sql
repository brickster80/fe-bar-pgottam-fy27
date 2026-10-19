CREATE OR REFRESH MATERIALIZED VIEW silver_devices
COMMENT 'CMDB devices: assignment to employee, managed state, loaner pool'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT device_id, hostname, device_type, cast(managed AS BOOLEAN) AS managed, assigned_employee_id,
  assignment_status, cast(assigned_since AS DATE) AS assigned_since
FROM bronze_devices
QUALIFY row_number() OVER (PARTITION BY device_id ORDER BY _ingested_at DESC, _source_file DESC) = 1;

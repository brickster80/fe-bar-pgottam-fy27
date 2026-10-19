CREATE OR REFRESH MATERIALIZED VIEW silver_employees (
  CONSTRAINT valid_email EXPECT (email LIKE '%@%') ON VIOLATION DROP ROW
)
COMMENT 'Business context: employee department, role, office, local timezone, manager'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT employee_id, full_name, email, department, role, office, timezone, manager_id
FROM bronze_hr_employees
QUALIFY row_number() OVER (PARTITION BY employee_id ORDER BY _ingested_at DESC, _source_file DESC) = 1;

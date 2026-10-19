CREATE OR REFRESH STREAMING TABLE silver_query_history (
  CONSTRAINT valid_statement EXPECT (statement_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_identity  EXPECT (executed_by IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT sane_rows       EXPECT (produced_rows >= 0)
)
COMMENT 'Query execution evidence: who ran which statement, from which client, how many rows it returned'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT statement_id, session_id, executed_by, execution_status, compute.warehouse_id AS warehouse_id,
  statement_text, statement_type, error_message, client_application,
  cast(total_duration_ms AS BIGINT) AS total_duration_ms,
  to_timestamp(start_time) AS start_time, to_timestamp(end_time) AS end_time,
  cast(read_rows AS BIGINT) AS read_rows, cast(produced_rows AS BIGINT) AS produced_rows, cast(read_bytes AS BIGINT) AS read_bytes
FROM STREAM(bronze_query_history);

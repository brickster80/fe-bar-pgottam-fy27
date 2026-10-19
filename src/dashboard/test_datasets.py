import re, sys
from databricks.sdk import WorkspaceClient
from datasets import DATASETS
w = WorkspaceClient()
for name, (_, q) in DATASETS.items():
    r = w.statement_execution.execute_statement(statement=q, warehouse_id=sys.argv[1], catalog="capmarkets_stg", schema="febar_e2e", wait_timeout="50s", row_limit=3)
    st = r.status.state.value
    n = r.manifest.total_row_count if r.manifest else None
    print(f"{name}: {st} rows={n}", (r.status.error.message[:200] if r.status.error else ""), (r.result.data_array[:1] if r.result and r.result.data_array else ""))

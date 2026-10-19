"""Run a ;-separated SQL file statement by statement on a SQL warehouse."""
import sys, re
from databricks.sdk import WorkspaceClient
w = WorkspaceClient()
wh = sys.argv[2]
sql = re.sub(r"--[^\n]*", "", open(sys.argv[1]).read())
for stmt in [s.strip() for s in sql.split(";\n") if s.strip()]:
    r = w.statement_execution.execute_statement(statement=stmt, warehouse_id=wh, wait_timeout="50s")
    state = r.status.state.value
    print(f"[{state}] {stmt.splitlines()[0][:100]}")
    if state != "SUCCEEDED":
        print("   ", r.status.error.message if r.status.error else "")

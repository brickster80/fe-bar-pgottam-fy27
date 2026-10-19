import sys
from databricks.sdk import WorkspaceClient
w = WorkspaceClient()
S = sys.argv[1]
for q in sys.argv[2:]:
    m = w.genie.start_conversation_and_wait(S, q)
    print(f"\nQ: {q}\n  status={m.status}")
    for a in m.attachments or []:
        if a.text: print("  text:", a.text.content[:300])
        if a.query:
            print("  sql:", " ".join(a.query.query.split())[:300])
            r = w.genie.get_message_attachment_query_result(S, m.conversation_id, m.id, a.attachment_id)
            for row in (r.statement_response.result.data_array or [])[:5]: print("   ", row)

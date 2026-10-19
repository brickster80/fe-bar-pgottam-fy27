"""Builds febar_e2e.lvdash.json - "Authorized access, unauthorized movement" AI/BI dashboard (4 question pages + global filters)."""
import json
from datasets import DATASETS

GENIE_SPACE_ID = "01f1cbe0c38c1d129f67a95d56d9ac69"
LABELS = {
    "event_date": "Date", "department": "Department", "resource": "Resource", "regulation": "Regulation",
    "full_name": "Identity", "destination_host": "Destination host", "pivot_host": "Pivot host",
    "severity_label": "Severity", "entitlement": "Entitlement", "channel": "Channel", "verdict": "Verdict",
    "measure(Alerts)": "Alerts", "sum(access_events)": "Accesses", "sum(denied_events)": "UC denials",
    "measure(Unauthorized Accesses)": "Non-authorized accesses", "count(path_id)": "Paths",
}
RED, AMBER, NAVY, TEAL, GREY = "#FF5F66", "#FFA600", "#4E5185", "#21918C", "#9AA5B1"

def dataset(name):
    display, sql = DATASETS[name]
    lines = [l + "\n" for l in sql.strip().splitlines()]
    ds = {"name": name, "displayName": display, "queryLines": lines}
    if name in MEASURES:
        ds["columns"] = [{"displayName": d, "expression": e} for d, e in MEASURES[name]]
    return ds


def pos(x, y, w, h):
    return {"x": x, "y": y, "width": w, "height": h}


def text(name, md, p):
    return {"widget": {"name": name, "multilineTextboxSpec": {"lines": md}}, "position": p}


def counter(name, ds, measure, title, p):
    f = f"measure({measure})"
    return {"widget": {"name": name,
        "queries": [{"name": "main_query", "query": {"datasetName": ds,
                     "fields": [{"name": f, "expression": f"MEASURE(`{measure}`)"}], "disaggregated": False}}],
        "spec": {"version": 2, "widgetType": "counter",
                 "encodings": {"value": {"fieldName": f, "displayName": title,
                                         "format": {"type": "number-plain", "abbreviation": "compact"}}},
                 "frame": {"title": title, "showTitle": True}}}, "position": p}


def field(c):
    return {"name": c, "expression": f"`{c}`"}


def bar(name, ds, title, x_field, x_expr, y_field, y_expr, color=None, mappings=None, horizontal=False,
        stacked=True, p=None, desc=None, x_temporal=False):
    fields = [{"name": x_field, "expression": x_expr}, {"name": y_field, "expression": y_expr}]
    cat_axis = {"fieldName": x_field, "scale": {"type": "temporal" if x_temporal else "categorical"}, "displayName": LABELS.get(x_field, x_field)}
    val_axis = {"fieldName": y_field, "scale": {"type": "quantitative"}, "displayName": LABELS.get(y_field, y_field)}
    enc = {"x": val_axis, "y": cat_axis} if horizontal else {"x": cat_axis, "y": val_axis}
    if horizontal:
        enc["y"]["scale"]["sort"] = {"by": "x-reversed"}
    if color:
        fields.append(field(color))
        cs = {"type": "categorical"}
        if mappings:
            cs["mappings"] = [{"value": v, "color": c} for v, c in mappings]
        enc["color"] = {"fieldName": color, "scale": cs, "displayName": LABELS.get(color, color)}
    spec = {"version": 3, "widgetType": "bar", "encodings": enc,
            "frame": {"showTitle": True, "title": title, **({"showDescription": True, "description": desc} if desc else {})}}
    if color and stacked:
        spec["mark"] = {"layout": "stack"}
    return {"widget": {"name": name, "queries": [{"name": "main_query", "query": {
        "datasetName": ds, "fields": fields, "disaggregated": False}}], "spec": spec}, "position": p}


def table(name, ds, title, cols, order_expr, p, desc=None, risk_col=None):
    columns = []
    for c, label in cols:
        col = {"fieldName": c, "displayName": label}
        if c == risk_col:
            col["style"] = {"type": "basic", "rules": [
                {"condition": {"operand": {"type": "data-value", "value": "80"}, "operator": ">="}, "backgroundColor": {"hex": RED}},
                {"condition": {"operand": {"type": "data-value", "value": "60"}, "operator": ">="}, "backgroundColor": {"hex": AMBER}}]}
        columns.append(col)
    return {"widget": {"name": name, "queries": [{"name": "main_query", "query": {
        "datasetName": ds, "fields": [field(c) for c, _ in cols], "disaggregated": True,
        "orders": [{"direction": d, "expression": e} for e, d in order_expr]}}],
        "spec": {"version": 2, "widgetType": "table", "encodings": {"columns": columns},
                 "frame": {"showTitle": True, "title": title, **({"showDescription": True, "description": desc} if desc else {})}}},
        "position": p}



LABELS.update({"asset": "Governed asset", "workflow_context": "Workflow context", "device_context": "Device",
               "sum(produced_rows)": "Rows returned", "count(statement_id)": "Queries", "access_date": "Date",
               "movement": "Movement", "count(chain_id)": "Chains", "volume_verdict": "Volume vs baseline",
               "count(anomaly_id)": "Employee-asset-days", "ml_label": "ML verdict", "count(feature_id)": "Employee-days",
               "priority": "Priority", "count(incident_id)": "Incidents"})

MEASURES = {
    "ds_access": [("Sensitive Queries", "COUNT(`statement_id`)"),
                  ("Employees On Restricted Assets", "COUNT(DISTINCT CASE WHEN `sensitivity_rank` >= 3 THEN `full_name` END)"),
                  ("Off-hours Sensitive Queries", "SUM(CASE WHEN `is_off_hours` THEN 1 ELSE 0 END)"),
                  ("Unassigned Device Queries", "SUM(CASE WHEN `device_context` = 'Unassigned device' THEN 1 ELSE 0 END)")],
    "ds_anomalies": [("Unusual Employee-Asset-Days", "SUM(CASE WHEN `volume_verdict` = 'Unusual' THEN 1 ELSE 0 END)"),
                     ("First Access To Restricted", "SUM(CASE WHEN `is_first_access_to_asset` AND `sensitivity` <> 'confidential' THEN 1 ELSE 0 END)"),
                     ("Max Ratio vs Self", "MAX(`ratio_vs_self`)")],
    "ds_ml": [("Anomalous Employee-Days", "SUM(CASE WHEN `is_anomaly` THEN 1 ELSE 0 END)")],
    "ds_chains": [("Files Materialized", "COUNT(`chain_id`)"),
                  ("Unauthorized Movements", "SUM(CASE WHEN `chain_stage` = 'uploaded_unauthorized' THEN 1 ELSE 0 END)"),
                  ("Approved Movements", "SUM(CASE WHEN `chain_stage` = 'uploaded_approved' THEN 1 ELSE 0 END)")],
    "ds_incidents": [("P1 Incidents", "SUM(CASE WHEN `priority` = 'P1' THEN 1 ELSE 0 END)"),
                     ("Candidate Incidents", "COUNT(`incident_id`)"),
                     ("Explained By Exception", "SUM(CASE WHEN `exception_ticket` IS NOT NULL THEN 1 ELSE 0 END)")],
}

WF = [("Outside workflow", RED), ("Exception ticket", AMBER), ("Approved workflow", TEAL)]
MOVE = [("Unauthorized destination", RED), ("Approved corporate tenant", TEAL), ("Local file only", GREY)]
VOL = [("Unusual", RED), ("Within baseline", GREY)]
PRIO = [("P1", RED), ("P2", AMBER), ("P3", NAVY), ("P4", GREY)]

q1 = [
    text("q1-title", ["# Q1 - Who accessed sensitive financial data?\n",
                      "Databricks **audit** (identity, source IP), **query history** (statement, rows, client) and **table lineage** (statement -> governed table), "
                      "joined to HR and the identity provider. Governed assets: `reporting.monthly_summary` (confidential), "
                      "`treasury.vendor_bank_accounts` (restricted), `strategy.acquisition_forecast` (highly restricted). *Synthetic data; Halcyon Financial is fictional.*"], pos(0, 0, 12, 2)),
    counter("kpi-q1-q", "ds_access", "Sensitive Queries", "Queries on sensitive financial assets", pos(0, 2, 3, 3)),
    counter("kpi-q1-e", "ds_access", "Employees On Restricted Assets", "Employees on restricted assets", pos(3, 2, 3, 3)),
    counter("kpi-q1-o", "ds_access", "Off-hours Sensitive Queries", "Off-hours sensitive queries", pos(6, 2, 3, 3)),
    counter("kpi-q1-d", "ds_access", "Unassigned Device Queries", "Queries from an unassigned device", pos(9, 2, 3, 3)),
    bar("q1-asset-wf", "ds_access", "Most sensitive reads happen inside an approved workflow", "asset", "`asset`",
        "count(statement_id)", "COUNT(`statement_id`)", color="workflow_context", mappings=WF, horizontal=True, p=pos(0, 5, 6, 6)),
    bar("q1-dept", "ds_access", "Rows returned by department and asset", "department", "`department`",
        "sum(produced_rows)", "SUM(`produced_rows`)", color="asset", horizontal=True, p=pos(6, 5, 6, 6)),
    bar("q1-daily", "ds_access", "Daily rows returned from governed assets - one night stands out", "access_date", "`access_date`",
        "sum(produced_rows)", "SUM(`produced_rows`)", color="asset", p=pos(0, 11, 12, 6), x_temporal=True),
    table("q1-detail", "ds_access", "Statement-level access (largest first)",
          [("access_date", "Date"), ("full_name", "Employee"), ("role", "Role"), ("department", "Dept"), ("asset", "Asset"),
           ("sensitivity", "Sensitivity"), ("produced_rows", "Rows"), ("client_application", "Client"), ("device_context", "Device"),
           ("workflow_context", "Workflow"), ("is_off_hours", "Off-hours")],
          [("`produced_rows`", "DESC")], pos(0, 17, 12, 7)),
]
q2 = [
    text("q2-title", ["# Q2 - Was the access unusual for that employee and their peers?\n",
                      "Each employee-asset-day is compared with the employee's own median day and with department peers on the same asset; "
                      "an Isolation Forest scores every employee-day across identity, data-access, endpoint and DLP features."], pos(0, 0, 12, 2)),
    counter("kpi-q2-u", "ds_anomalies", "Unusual Employee-Asset-Days", "Unusual vs self or peers", pos(0, 2, 4, 3)),
    counter("kpi-q2-f", "ds_anomalies", "First Access To Restricted", "First-ever access to a restricted asset", pos(4, 2, 4, 3)),
    counter("kpi-q2-m", "ds_ml", "Anomalous Employee-Days", "ML-anomalous employee-days", pos(8, 2, 4, 3)),
    {"widget": {"name": "q2-scatter", "queries": [{"name": "main_query", "query": {"datasetName": "ds_anomalies",
        "fields": [field("ratio_vs_self"), field("ratio_vs_peers"), field("volume_verdict"), field("full_name")], "disaggregated": True}}],
        "spec": {"version": 3, "widgetType": "scatter",
                 "frame": {"showTitle": True, "title": "One employee-day is far outside both baselines",
                           "showDescription": True, "description": "x = rows vs employee median day, y = rows vs peer median for the asset"},
                 "encodings": {"x": {"fieldName": "ratio_vs_self", "scale": {"type": "quantitative"}, "displayName": "x self baseline"},
                               "y": {"fieldName": "ratio_vs_peers", "scale": {"type": "quantitative"}, "displayName": "x peer baseline"},
                               "color": {"fieldName": "volume_verdict", "scale": {"type": "categorical",
                                         "mappings": [{"value": v, "color": c} for v, c in VOL]}, "displayName": "Volume"}}}},
     "position": pos(0, 5, 6, 7)},
    bar("q2-ml", "ds_ml", "ML anomaly verdicts by department", "department", "`department`",
        "count(feature_id)", "COUNT(`feature_id`)", color="ml_label", mappings=[("Anomalous", RED), ("Normal", GREY)], horizontal=True, p=pos(6, 5, 6, 7)),
    table("q2-detail", "ds_anomalies", "Employee x asset x day vs baselines",
          [("access_date", "Date"), ("full_name", "Employee"), ("department", "Dept"), ("asset", "Asset"), ("rows_returned", "Rows"),
           ("user_median_daily_rows", "Employee median day"), ("ratio_vs_self", "x self"), ("peer_median_daily_rows", "Peer median"),
           ("ratio_vs_peers", "x peers"), ("is_first_access_to_asset", "First access"), ("unassigned_device", "Unassigned device"), ("volume_verdict", "Verdict")],
          [("`ratio_vs_peers`", "DESC")], pos(0, 12, 12, 7)),
]
q3 = [
    text("q3-title", ["# Q3 - Did the data move to an unauthorized destination?\n",
                      "A chain links a sensitive query to a file created on the **same device** by the **same client process** within 15 minutes "
                      "(size consistent with the result set), and to a DLP-observed upload of the **same SHA-256**."], pos(0, 0, 12, 2)),
    counter("kpi-q3-f", "ds_chains", "Files Materialized", "Sensitive results saved to files", pos(0, 2, 4, 3)),
    counter("kpi-q3-a", "ds_chains", "Approved Movements", "Moved to the corporate tenant", pos(4, 2, 4, 3)),
    counter("kpi-q3-u", "ds_chains", "Unauthorized Movements", "Moved to an unauthorized destination", pos(8, 2, 4, 3)),
    bar("q3-move", "ds_chains", "Where sensitive files went", "asset", "`asset`", "count(chain_id)", "COUNT(`chain_id`)",
        color="movement", mappings=MOVE, horizontal=True, p=pos(0, 5, 6, 6)),
    bar("q3-app", "ds_chains", "Destination apps", "upload_app", "`upload_app`", "count(chain_id)", "COUNT(`chain_id`)",
        color="movement", mappings=MOVE, horizontal=True, p=pos(6, 5, 6, 6)),
    table("q3-detail", "ds_chains", "Access -> file -> destination chains",
          [("access_date", "Date"), ("movement", "Movement"), ("full_name", "Employee"), ("department", "Dept"), ("asset", "Asset"),
           ("produced_rows", "Rows"), ("client_application", "Client"), ("device_hostname", "Device"), ("file_name", "File"),
           ("file_mb", "MB"), ("upload_app", "Destination"), ("instance_type", "Instance"), ("destination_account", "Account")],
          [("`chain_stage`", "DESC"), ("`produced_rows`", "DESC")], pos(0, 11, 12, 7)),
]
q4 = [
    text("q4-title", ["# Q4 - What evidence supports the threat assessment?\n",
                      "Correlation converts separate identity, data-access, file and upload alerts into one explainable incident. "
                      "The assessment weighs two competing hypotheses - **insider misuse of legitimate access** vs **account or device compromise** - without assuming intent."], pos(0, 0, 12, 2)),
    counter("kpi-q4-p1", "ds_incidents", "P1 Incidents", "P1 incidents", pos(0, 2, 4, 3)),
    counter("kpi-q4-c", "ds_incidents", "Candidate Incidents", "Candidate incidents", pos(4, 2, 4, 3)),
    counter("kpi-q4-x", "ds_incidents", "Explained By Exception", "Explained by an exception ticket", pos(8, 2, 4, 3)),
    table("q4-incidents", "ds_incidents", "Incidents ranked by fused risk (rules 60% + ML 40%)",
          [("priority", "Priority"), ("fused_risk", "Fused risk"), ("access_date", "Date"), ("full_name", "Employee"), ("department", "Dept"),
           ("asset", "Asset"), ("chain_stage", "Chain"), ("leading_hypothesis", "Leading hypothesis (GenAI)"), ("attack_techniques", "ATT&CK"),
           ("compromise_indicators", "Compromise indicators"), ("misuse_indicators", "Misuse indicators"), ("mitigating_factors", "Mitigating")],
          [("`fused_risk`", "DESC")], pos(0, 5, 12, 6), risk_col="fused_risk"),
    table("q4-timeline", "ds_timeline", "Evidence timeline (employee local time) - filter Employee = Alex Morgan",
          [("priority", "Priority"), ("full_name", "Employee"), ("access_date", "Date"), ("local_hhmm", "Local"), ("source", "Source"),
           ("observation", "Observation"), ("why_it_matters", "Why it matters"), ("evidence_ref", "Evidence ref")],
          [("`priority`", "ASC"), ("`incident_id`", "ASC"), ("`step`", "ASC")], pos(0, 11, 12, 8)),
]

ALL_DATE = ["ds_access", "ds_anomalies", "ds_ml", "ds_chains", "ds_incidents", "ds_timeline"]


def global_filter(name, wtype, col, dss, title, p):
    return {"widget": {"name": name,
        "queries": [{"name": f"{name}_{d}", "query": {"datasetName": d, "fields": [field(col)], "disaggregated": False}} for d in dss],
        "spec": {"version": 2, "widgetType": wtype,
                 "encodings": {"fields": [{"fieldName": col, "displayName": title, "queryName": f"{name}_{d}"} for d in dss]},
                 "frame": {"showTitle": True, "title": title}}}, "position": p}


filters = [
    global_filter("f-date", "filter-date-range-picker", "access_date", ALL_DATE, "Date", pos(0, 0, 4, 2)),
    global_filter("f-dept", "filter-multi-select", "department", ALL_DATE, "Department", pos(4, 0, 4, 2)),
    global_filter("f-emp", "filter-multi-select", "full_name", ALL_DATE, "Employee", pos(8, 0, 4, 2)),
]

dash = {
    "datasets": [dataset(n) for n in DATASETS],
    "pages": [
        {"name": "q1_who", "displayName": "Q1 Who accessed", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1", "layout": q1},
        {"name": "q2_unusual", "displayName": "Q2 Unusual?", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1", "layout": q2},
        {"name": "q3_moved", "displayName": "Q3 Did it move?", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1", "layout": q3},
        {"name": "q4_evidence", "displayName": "Q4 Evidence", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1", "layout": q4},
        {"name": "filters", "displayName": "Filters", "pageType": "PAGE_TYPE_GLOBAL_FILTERS", "layoutVersion": "GRID_V1", "layout": filters},
    ],
    "uiSettings": {
        "theme": {
            "canvasBackgroundColor": {"light": "#FCFCFC", "dark": "#1F272D"},
            "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#11171C"},
            "widgetBorderColor": {"light": "#FFFFFF", "dark": "#11171C"},
            "fontColor": {"light": "#11171C", "dark": "#E8ECF0"},
            "selectionColor": {"light": "#2272B4", "dark": "#8ACAFF"},
            "visualizationColors": ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#D55E00", "#56B4E9", "#F0E442"],
            "widgetHeaderAlignment": "LEFT",
        },
        "genieSpace": {"isEnabled": True, "overrideId": GENIE_SPACE_ID, "enablementMode": "ENABLED"},
    },
}

for page in dash["pages"]:
    rows = {}
    for l in page["layout"]:
        rows[l["position"]["y"]] = rows.get(l["position"]["y"], 0) + l["position"]["width"]
    bad = {y: w for y, w in rows.items() if w != 12}
    assert not bad, (page["name"], bad)

json.dump(dash, open("febar_e2e.lvdash.json", "w"), indent=1)
print("widgets:", sum(len(p["layout"]) for p in dash["pages"]))

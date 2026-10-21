"""
"Authorized access, unauthorized movement" - synthetic raw data generator
=========================================================================
Fictional company: Harborview Investment Management (harborviewim.com), a fund and portfolio manager. Lands RAW feeds in
/Volumes/capmarkets_stg/febar_e2e/raw_landing/ for Lakeflow to ingest, and creates
the physical stand-ins for the three governed investment assets.

Databricks-side feeds (shaped like the system tables):
  uc_audit/        system.access.audit       (getTable, generateTemporaryTableCredential, commandSubmit)
  query_history/   system.query.history      (statement_id, executed_by, produced_rows, client_application ...)
  table_lineage/   system.access.table_lineage (statement_id -> source_table_full_name)
External feeds (proposed inputs):
  idp/             Okta-style sign-ins (device, IP, factor, risk)
  endpoint/        EDR file-creation events (device, process, file, sha256, size)
  dlp/             Netskope-style DLP / proxy upload events (destination instance, account, sha256, bytes)
Business context:
  hr/ devices/ assets/ workflows/ exceptions/ calendar/

Incident (all times America/New_York local, 2026-09-24):
  21:40 Alex Morgan signs in from LOANER-NYC-07 (never associated with Alex)
  21:43 first-ever access to invest_prod.research.unpublished_ratings (pre-publication research)
  21:46 query returns 480,000 rows (normal daily volume ~8,000)
  21:49 EDR: DBeaver.exe creates research_pipeline_full.csv
  21:53 DLP: matching file (same sha256) uploaded to a personal Dropbox account
Decoys:
  Priya Shah (Compliance) - 52,000-row research surveillance pull under exception EXC-4471, uploaded to corporate SharePoint
  Daniel Okafor (Equity Research) - new managed laptop (device refresh), normal activity
  Kevin Brooks (Engineering) - personal Dropbox upload of photos, no sensitive data access

Run:  TZ=UTC DATABRICKS_CONFIG_PROFILE=e2-demo-field-eng python generate_raw.py
"""
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from databricks.connect import DatabricksSession
from pyspark.sql import functions as F
from pyspark.sql import types as T

CATALOG, SCHEMA = "capmarkets_stg", "febar_e2e"
FQ = f"{CATALOG}.{SCHEMA}"
VOL = f"/Volumes/{CATALOG}/{SCHEMA}/raw_landing"
DOMAIN = "harborviewim.com"
WAREHOUSE = "4b9b953939869799"          # fictional prod warehouse id in the logs
WORKSPACE_ID = "7474650000000001"

spark = DatabricksSession.builder.serverless(True).getOrCreate()

START, END = date(2026, 7, 1), date(2026, 9, 30)
N_USERS = 400

# logical governed assets (what the fictional company calls them) -> physical stand-ins in this schema
HOLDINGS = "invest_prod.portfolio.fund_holdings"
RATINGS = "invest_prod.research.unpublished_ratings"
ORDERS = "invest_prod.trading.pending_block_orders"
CRM = "clients_prod.crm.relationships"
WEB = "analytics_prod.web.sessions"

# ---------------------------------------------------------------------------
# Business calendar
# ---------------------------------------------------------------------------
days = [START + timedelta(d) for d in range((END - START).days + 1)]
bdays = [d for d in days if d.weekday() < 5]


def is_close(d):
    """Month-end reporting: last 3 and first 3 business days of each month (NAV, fund factsheets, client reports)."""
    same_month = [b for b in bdays if b.month == d.month]
    return d in same_month[:3] or d in same_month[-3:]


calendar_rows = [(d.isoformat(), d.weekday() < 5, d.weekday() < 5 and is_close(d),
                  "Month-end reporting" if d.weekday() < 5 and is_close(d) else ("Weekend" if d.weekday() >= 5 else "Business day"))
                 for d in days]

# ---------------------------------------------------------------------------
# HR
# ---------------------------------------------------------------------------
FIRST = ["James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael", "Linda", "David", "Elizabeth",
         "William", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Chris", "Karen",
         "Daniel", "Nancy", "Wei", "Fatima", "Diego", "Yuki", "Omar", "Anya", "Kofi", "Lena"]
LAST = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
        "Hernandez", "Lopez", "Wilson", "Anderson", "Taylor", "Moore", "Jackson", "Patel", "Nguyen", "Kim",
        "Chen", "Okafor", "Ivanov", "Haddad", "Singh", "Rossi", "Dubois", "Sato", "Novak", "Reyes"]
DEPTS = [("Portfolio Management", "Portfolio Analyst", 70), ("Compliance", "Compliance Analyst", 40), ("Equity Research", "Research Analyst", 20),
         ("Trading", "Equity Trader", 12), ("Engineering", "Software Engineer", 110),
         ("Client Service", "Relationship Manager", 80), ("IT", "IT Administrator", 28), ("HR", "HR Partner", 20), ("Legal", "Counsel", 20)]
OFFICES = [("New York", "America/New_York", "203.0.113.10", 0.6), ("Chicago", "America/Chicago", "203.0.113.20", 0.2),
           ("London", "Europe/London", "203.0.113.30", 0.2)]

emp = []
i = 0
for dept, role, n in DEPTS:
    for k in range(n):
        office = OFFICES[0] if (i % 10) < 6 else (OFFICES[1] if (i % 10) < 8 else OFFICES[2])
        first, last = FIRST[(i * 7) % 30], LAST[(i * 11 + 3) % 30]
        emp.append([i, f"E-{i:04d}", f"{first} {last}", dept, role if k > 1 else f"Senior {role}", office[0], office[1], office[2]])
        i += 1
PERSONAS = {  # idx -> (name, dept, role, office)
    42: ("Alex Morgan", "Portfolio Management", "Portfolio Analyst", OFFICES[0]),
    95: ("Priya Shah", "Compliance", "Senior Compliance Analyst", OFFICES[0]),
    118: ("Daniel Okafor", "Equity Research", "Research Analyst", OFFICES[0]),
    150: ("Kevin Brooks", "Engineering", "Software Engineer", OFFICES[1]),
}
for idx, (name, dept, role, office) in PERSONAS.items():
    emp[idx][2], emp[idx][3], emp[idx][4], emp[idx][5], emp[idx][6], emp[idx][7] = name, dept, role, office[0], office[1], office[2]
for e in emp:
    e.append(e[2].lower().replace(" ", ".") + (f".{e[0]}" if e[0] not in PERSONAS else "") + f"@{DOMAIN}")
    e.append(f"E-{(e[0] // 15) * 15:04d}")   # manager
EMP_IDX = {e[0]: e for e in emp}
ALEX = EMP_IDX[42]
emp_schema = "user_idx long, employee_id string, full_name string, department string, role string, office string, timezone string, office_ip string, email string, manager_id string"
emp_df = spark.createDataFrame([tuple(e) for e in emp], emp_schema)

# ---------------------------------------------------------------------------
# Devices (CMDB): one managed laptop per employee + loaner pool; Daniel gets a refresh
# ---------------------------------------------------------------------------
devices = [(f"DEV-{e[0]:04d}", f"HVI-LT-{e[0]:04d}", "laptop", True, e[1], "assigned", "2025-01-15") for e in emp]
devices += [(f"DEV-L{k:02d}", f"LOANER-NYC-{k:02d}", "loaner_laptop", True, None, "pool", "2024-06-01") for k in range(1, 11)]
devices.append(("DEV-0118B", "HVI-LT-0118B", "laptop", True, "E-0118", "assigned", "2026-09-21"))
dev_schema = "device_id string, hostname string, device_type string, managed boolean, assigned_employee_id string, assignment_status string, assigned_since string"

# ---------------------------------------------------------------------------
# Baseline activity: one session per user per active business day
# ---------------------------------------------------------------------------
ud = spark.createDataFrame([(d.isoformat(), is_close(d)) for d in bdays], "day string, close boolean") \
    .crossJoin(emp_df.select("user_idx", "employee_id", "email", "department", "timezone", "office_ip"))
ud = ud.where(F.rand(1) < 0.88)  # PTO / not working
ud = ud.withColumn("from_home", F.rand(2) < 0.35) \
    .withColumn("src_ip", F.when(F.col("from_home"), F.concat(F.lit("98.113."), (F.col("user_idx") % 250 + 1).cast("string"), F.lit(".77")))
                .otherwise(F.col("office_ip"))) \
    .withColumn("device_id", F.when((F.col("user_idx") == 118) & (F.col("day") >= "2026-09-21"), F.lit("DEV-0118B"))
                .otherwise(F.concat(F.lit("DEV-"), F.lpad(F.col("user_idx").cast("string"), 4, "0")))) \
    .withColumn("start_hour", (F.rand(3) * 3 + 7.5)) \
    .withColumn("session_id", F.concat(F.lit("S-"), F.col("employee_id"), F.lit("-"), F.regexp_replace("day", "-", ""))) \
    .withColumn("signin_local", F.expr("to_timestamp(day) + make_interval(0,0,0,0, cast(start_hour as int), cast((start_hour - cast(start_hour as int))*60 as int), 0)")) \
    .withColumn("signin_utc", F.to_utc_timestamp("signin_local", F.col("timezone")))
# materialize once so every feed derived from it sees identical random draws
ud.write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}._gen_user_days")
ud = spark.table(f"{FQ}._gen_user_days")

# IdP sign-ins
idp = ud.select(
    F.concat(F.lit("OKTA-"), F.col("session_id")).alias("uuid"), F.col("signin_utc").alias("published"),
    F.col("email"), F.col("device_id"), F.col("src_ip"), F.col("session_id"),
    F.when(F.col("from_home"), F.lit("home")).otherwise(F.lit("office")).alias("network"),
    F.when(F.rand(4) < 0.7, "okta_verify_push").otherwise("fido2_webauthn").alias("factor"),
    F.lit("SUCCESS").alias("outcome"), F.lit("LOW").alias("risk_level"), F.lit(True).alias("device_trusted"))

# Queries: asset mix by department
q = ud.withColumn("nq", F.when(F.col("department").isin("Portfolio Management", "Compliance", "Equity Research", "Trading"),
                               (F.rand(5) * 3 + 2).cast("int")).otherwise((F.rand(5) * 3).cast("int")))
q = q.withColumn("qi", F.explode(F.sequence(F.lit(1), F.greatest(F.col("nq"), F.lit(1))))).where(F.col("nq") > 0)
r = F.rand(6)
q = q.withColumn("asset",
    F.when(F.col("department") == "Portfolio Management",
           F.when((r < 0.012) & (F.col("user_idx") != 42), F.lit(RATINGS)).when(r < 0.85, F.lit(HOLDINGS)).otherwise(F.lit(CRM)))
     .when(F.col("department") == "Compliance", F.when(r < 0.10, F.lit(RATINGS)).when(r < 0.70, F.lit(HOLDINGS)).otherwise(F.lit(CRM)))
     .when(F.col("department") == "Equity Research", F.when(r < 0.70, F.lit(RATINGS)).otherwise(F.lit(HOLDINGS)))
     .when(F.col("department") == "Trading", F.when(r < 0.60, F.lit(ORDERS)).otherwise(F.lit(HOLDINGS)))
     .when(F.col("department") == "Client Service", F.lit(CRM))
     .otherwise(F.when(r < 0.003, F.lit(ORDERS)).otherwise(F.lit(WEB))))
base_rows = F.when(F.col("asset") == HOLDINGS, F.exp(F.randn(7) * 0.35) * 2600) \
    .when(F.col("asset") == RATINGS, F.exp(F.randn(7) * 0.5) * 450) \
    .when(F.col("asset") == ORDERS, F.exp(F.randn(7) * 0.4) * 140) \
    .otherwise(F.exp(F.randn(7) * 0.8) * 9000)
q = q.withColumn("produced_rows", (base_rows * F.when(F.col("close") & (F.col("asset") == HOLDINGS), 2.5).otherwise(1.0)).cast("long"))
q = q.withColumn("denied", (F.col("asset") == ORDERS) & ~F.col("department").isin("Trading"))
q = q.withColumn("produced_rows", F.when(F.col("denied"), F.lit(0)).otherwise(F.col("produced_rows")))
q = q.withColumn("client_application",
    F.when(F.col("department").isin("Engineering", "IT"), F.element_at(F.array(F.lit("Databricks SQL Editor"), F.lit("Databricks Notebook"), F.lit("DBeaver 24.1")), (F.rand(8) * 3).cast("int") + 1))
     .otherwise(F.element_at(F.array(F.lit("Databricks SQL Editor"), F.lit("Power BI"), F.lit("Microsoft Excel (ODBC)")), (F.rand(8) * 3).cast("int") + 1)))
q = q.withColumn("q_local", F.col("signin_local") + F.make_interval(F.lit(0), F.lit(0), F.lit(0), F.lit(0), (F.col("qi") * 1.7 + F.rand(9) * 1.5).cast("int"), (F.rand(10) * 59).cast("int"), (F.rand(11) * 59).cast("int"))) \
    .withColumn("start_time", F.to_utc_timestamp("q_local", F.col("timezone"))) \
    .withColumn("duration_ms", (F.col("produced_rows") * 0.4 + F.rand(12) * 3000 + 400).cast("long")) \
    .withColumn("end_time", F.col("start_time") + F.make_interval(F.lit(0), F.lit(0), F.lit(0), F.lit(0), F.lit(0), F.lit(0), F.col("duration_ms") / 1000)) \
    .withColumn("statement_id", F.expr("concat_ws('-', substr(md5(concat(session_id, qi)), 1, 8), substr(md5(concat(session_id, qi)), 9, 4), substr(md5(concat(session_id, qi)), 13, 4), substr(md5(concat(session_id, qi)), 17, 4), substr(md5(concat(session_id, qi)), 21, 12))")) \
    .withColumn("row_bytes", F.when(F.col("asset") == RATINGS, 180).when(F.col("asset") == HOLDINGS, 120).when(F.col("asset") == ORDERS, 300).otherwise(90))
QCOLS = ["statement_id", "session_id", "email", "employee_id", "user_idx", "device_id", "src_ip", "asset", "produced_rows",
         "denied", "client_application", "start_time", "end_time", "duration_ms", "row_bytes", "timezone", "department"]
q = q.select(*QCOLS)
q.write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}._gen_queries")
q = spark.table(f"{FQ}._gen_queries")

# Benign file exports from investment-team queries via Excel / Power BI, most saved to corporate SharePoint
ex = q.where(F.col("department").isin("Portfolio Management", "Compliance", "Equity Research") & F.col("client_application").isin("Microsoft Excel (ODBC)", "Power BI")
             & ~F.col("denied") & (F.rand(13) < 0.12))
ex = ex.withColumn("file_name", F.concat(F.regexp_replace(F.element_at(F.split("asset", "\\."), 3), "_", "-"), F.lit("_"),
                                         F.date_format("start_time", "yyyyMMdd"), F.lit(".xlsx"))) \
    .withColumn("process_name", F.when(F.col("client_application") == "Power BI", F.lit("PBIDesktop.exe")).otherwise(F.lit("EXCEL.EXE"))) \
    .withColumn("size_bytes", (F.col("produced_rows") * F.col("row_bytes") * 0.6).cast("long")) \
    .withColumn("file_time", F.col("end_time") + F.make_interval(F.lit(0), F.lit(0), F.lit(0), F.lit(0), F.lit(0), (F.rand(14) * 4 + 1).cast("int"), F.lit(0))) \
    .withColumn("sha256", F.sha2(F.concat_ws("|", "statement_id", "file_name"), 256))
endpoint_benign = ex.select(F.concat(F.lit("EDR-"), F.col("statement_id")).alias("event_id"), F.col("file_time").alias("timestamp"),
                            "device_id", "email", "process_name",
                            F.concat(F.lit("C:\\Users\\"), F.split("email", "@").getItem(0), F.lit("\\Documents\\"), F.col("file_name")).alias("file_path"),
                            "file_name", "sha256", "size_bytes")
dlp_benign = ex.where(F.rand(15) < 0.5).select(
    F.concat(F.lit("DLP-"), F.col("statement_id")).alias("event_id"),
    (F.col("file_time") + F.make_interval(F.lit(0), F.lit(0), F.lit(0), F.lit(0), F.lit(0), (F.rand(16) * 20 + 2).cast("int"), F.lit(0))).alias("timestamp"),
    "email", "device_id", F.lit("Microsoft SharePoint").alias("app"), F.lit("corporate").alias("instance_type"),
    F.lit("harborviewim.sharepoint.com").alias("destination"), F.lit("tenant:harborviewim").alias("destination_account"),
    "file_name", "sha256", F.col("size_bytes").alias("bytes"), F.lit("Upload").alias("activity"),
    F.lit("allow").alias("action"), F.lit("success").alias("outcome"), F.lit("Corporate collaboration").alias("policy"),
    F.lit(None).cast("string").alias("dlp_profile"))
# Background personal uploads with no sensitive content (DLP noise)
dlp_noise = ud.where(F.rand(17) < 0.012).select(
    F.concat(F.lit("DLP-N-"), F.col("session_id")).alias("event_id"),
    (F.col("signin_utc") + F.make_interval(F.lit(0), F.lit(0), F.lit(0), F.lit(0), F.lit(4), F.lit(10), F.lit(0))).alias("timestamp"),
    "email", "device_id", F.lit("Google Drive").alias("app"), F.lit("personal").alias("instance_type"),
    F.lit("drive.google.com").alias("destination"), F.concat(F.lit("gdrive-personal:"), F.substring(F.sha2("email", 256), 1, 10)).alias("destination_account"),
    F.lit("photos_weekend.zip").alias("file_name"), F.sha2("session_id", 256).alias("sha256"), (F.rand(18) * 30e6).cast("long").alias("bytes"),
    F.lit("Upload").alias("activity"), F.lit("allow").alias("action"), F.lit("success").alias("outcome"),
    F.lit("Personal cloud - monitor").alias("policy"), F.lit(None).cast("string").alias("dlp_profile"))

# ---------------------------------------------------------------------------
# Scripted personas
# ---------------------------------------------------------------------------
NY = ZoneInfo("America/New_York")
UTC = ZoneInfo("UTC")


def utc(local_str, tz=NY):
    return datetime.fromisoformat(local_str).replace(tzinfo=tz).astimezone(UTC).replace(tzinfo=None)


ALEX_EMAIL, ALEX_ID = ALEX[8], ALEX[1]
LOANER, LOANER_IP = "DEV-L07", "73.45.201.18"
ALEX_SESSION = "S-E-0042-20260924-N"
SHA_ALEX = "9f2c6a1e4b7d0c3f8a5e2d1b6c9f0a3e7d4b1c8f5a2e9d6b3c0f7a4e1d8b5c2f"
q_schema = q.schema

scripted_q, scripted_idp, scripted_ep, scripted_dlp = [], [], [], []
# 21:40 sign-in from loaner device never associated with Alex
scripted_idp.append(("OKTA-" + ALEX_SESSION, utc("2026-09-24T21:40:12"), ALEX_EMAIL, LOANER, LOANER_IP, ALEX_SESSION,
                     "home", "okta_verify_push", "SUCCESS", "MEDIUM", True))
# 21:43 first-ever access to unpublished research (schema probe), 21:46 bulk pull 480,000 rows
scripted_q.append(("01f0a7c2-alex-0001-probe", ALEX_SESSION, ALEX_EMAIL, ALEX_ID, 42, LOANER, LOANER_IP, RATINGS, 25, False,
                   "DBeaver 24.1", utc("2026-09-24T21:43:05"), utc("2026-09-24T21:43:06"), 900, 180, "America/New_York", "Portfolio Management"))
scripted_q.append(("01f0a7c2-alex-0002-bulk", ALEX_SESSION, ALEX_EMAIL, ALEX_ID, 42, LOANER, LOANER_IP, RATINGS, 480000, False,
                   "DBeaver 24.1", utc("2026-09-24T21:46:10"), utc("2026-09-24T21:47:52"), 102000, 180, "America/New_York", "Portfolio Management"))
# 21:49 EDR: CSV materialized by the client process
scripted_ep.append(("EDR-ALEX-0001", utc("2026-09-24T21:49:31"), LOANER, ALEX_EMAIL, "dbeaver.exe",
                    "C:\\Users\\amorgan\\Downloads\\research_pipeline_full.csv", "research_pipeline_full.csv", SHA_ALEX, 86_400_000))
# 21:53 DLP: upload of the same file to an unapproved personal Dropbox account
scripted_dlp.append(("DLP-ALEX-0001", utc("2026-09-24T21:53:44"), ALEX_EMAIL, LOANER, "Dropbox", "personal", "www.dropbox.com",
                     "dropbox-personal:dbid:AAD7Kx2mQ9", "research_pipeline_full.csv", SHA_ALEX, 86_400_000, "Upload", "allow",
                     "success", "Personal cloud - monitor", "Unpublished research / price targets"))

# Priya Shah decoy: large research-surveillance pull under exception ticket, corporate destination, business hours
PRIYA = EMP_IDX[95]
SHA_PRIYA = "1b3d5f7a9c2e4f6a8b0d1c3e5f7a9b2d4c6e8f0a1b3d5f7a9c2e4f6a8b0d1c3e"
PS = "S-E-0095-20260929-X"
scripted_idp.append(("OKTA-" + PS, utc("2026-09-29T13:55:00"), PRIYA[8], "DEV-0095", "203.0.113.10", PS, "office", "fido2_webauthn", "SUCCESS", "LOW", True))
scripted_q.append(("01f0b113-priya-0001-audit", PS, PRIYA[8], PRIYA[1], 95, "DEV-0095", "203.0.113.10", RATINGS, 52000, False,
                   "Microsoft Excel (ODBC)", utc("2026-09-29T14:05:00"), utc("2026-09-29T14:05:31"), 31000, 180, "America/New_York", "Compliance"))
scripted_ep.append(("EDR-PRIYA-0001", utc("2026-09-29T14:08:10"), "DEV-0095", PRIYA[8], "EXCEL.EXE",
                    "C:\\Users\\pshah\\Documents\\research_surveillance_Q3.xlsx", "research_surveillance_Q3.xlsx", SHA_PRIYA, 5_600_000))
scripted_dlp.append(("DLP-PRIYA-0001", utc("2026-09-29T14:15:02"), PRIYA[8], "DEV-0095", "Microsoft SharePoint", "corporate",
                     "harborviewim.sharepoint.com", "tenant:harborviewim", "research_surveillance_Q3.xlsx", SHA_PRIYA, 5_600_000,
                     "Upload", "allow", "success", "Corporate collaboration", "Unpublished research / price targets"))
# Kevin Brooks decoy: personal Dropbox upload, nothing sensitive accessed
KEV = EMP_IDX[150]
scripted_dlp.append(("DLP-KEVIN-0001", utc("2026-09-23T19:12:00", ZoneInfo("America/Chicago")), KEV[8], "DEV-0150", "Dropbox", "personal",
                     "www.dropbox.com", "dropbox-personal:dbid:KQ81zz", "family_videos.mp4", "c" * 64, 410_000_000,
                     "Upload", "allow", "success", "Personal cloud - monitor", None))

q_all = q.unionByName(spark.createDataFrame(scripted_q, q_schema))
idp_all = idp.unionByName(spark.createDataFrame(scripted_idp, idp.schema))
ep_all = endpoint_benign.unionByName(spark.createDataFrame(scripted_ep, endpoint_benign.schema))
dlp_all = dlp_benign.unionByName(dlp_noise).unionByName(spark.createDataFrame(scripted_dlp, dlp_benign.schema))

# ---------------------------------------------------------------------------
# Shape the Databricks-side feeds like the system tables
# ---------------------------------------------------------------------------
qh = q_all.select(
    F.lit(WORKSPACE_ID).alias("workspace_id"), "statement_id", "session_id",
    F.when(F.col("denied"), "FAILED").otherwise("FINISHED").alias("execution_status"),
    F.struct(F.lit("WAREHOUSE").alias("type"), F.lit(WAREHOUSE).alias("warehouse_id")).alias("compute"),
    F.col("email").alias("executed_by"),
    F.concat(F.lit("SELECT * FROM "), F.col("asset"),
             F.when(F.col("produced_rows") > 100000, F.lit("")).otherwise(F.lit(" WHERE period >= add_months(current_date(), -1)"))).alias("statement_text"),
    F.lit("SELECT").alias("statement_type"),
    F.when(F.col("denied"), F.lit("[INSUFFICIENT_PERMISSIONS] User does not have SELECT on Table")).alias("error_message"),
    "client_application", F.col("duration_ms").alias("total_duration_ms"),
    F.date_format("start_time", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").alias("start_time"),
    F.date_format("end_time", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").alias("end_time"),
    F.col("produced_rows").alias("read_rows"), "produced_rows",
    (F.col("produced_rows") * F.col("row_bytes")).alias("read_bytes"))

lin = q_all.where(~F.col("denied")).select(
    F.lit(WORKSPACE_ID).alias("workspace_id"), F.lit("DBSQL_QUERY").alias("entity_type"),
    F.col("statement_id"), F.col("asset").alias("source_table_full_name"), F.lit("TABLE").alias("source_type"),
    F.lit(None).cast("string").alias("target_table_full_name"), F.lit(None).cast("string").alias("target_type"),
    F.col("email").alias("created_by"), F.date_format("start_time", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").alias("event_time"))

aud_base = q_all.select("statement_id", "email", "src_ip", "asset", "denied", "client_application", "start_time")
ua = F.when(F.col("client_application").startswith("DBeaver"), F.lit("DBeaver/24.1 Databricks-JDBC/2.6.40")) \
    .when(F.col("client_application") == "Power BI", F.lit("PowerBI/2.140 Simba-ODBC")) \
    .when(F.col("client_application").startswith("Microsoft Excel"), F.lit("Excel/16.0 Simba-ODBC")) \
    .otherwise(F.lit("Mozilla/5.0 Databricks-SQL-Editor"))


def audit(df, service, action, params):
    return df.select(
        F.date_format("start_time", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").alias("event_time"),
        F.to_date("start_time").cast("string").alias("event_date"), F.lit(WORKSPACE_ID).alias("workspace_id"),
        F.lit(service).alias("service_name"), F.lit(action).alias("action_name"),
        F.concat(F.lit(action[:3].upper() + "-"), F.col("statement_id")).alias("request_id"),
        F.struct(F.col("email").alias("email")).alias("user_identity"),
        params.alias("request_params"),
        F.struct(F.when(F.col("denied") & (F.lit(service) == "unityCatalog"), 403).otherwise(200).alias("status_code"),
                 F.when(F.col("denied") & (F.lit(service) == "unityCatalog"), F.lit("PERMISSION_DENIED")).alias("error_message")).alias("response"),
        F.col("src_ip").alias("source_ip_address"), ua.alias("user_agent"))


aud = audit(aud_base, "unityCatalog", "getTable",
            F.struct(F.col("asset").alias("full_name_arg"), F.lit(None).cast("string").alias("commandId"), F.lit(None).cast("string").alias("warehouseId"))) \
    .unionByName(audit(aud_base, "databrickssql", "commandSubmit",
                       F.struct(F.lit(None).cast("string").alias("full_name_arg"), F.col("statement_id").alias("commandId"), F.lit(WAREHOUSE).alias("warehouseId"))))

# ---------------------------------------------------------------------------
# Write raw feeds
# ---------------------------------------------------------------------------
def ts_str(df, col):
    return df.withColumn(col, F.date_format(col, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"))


print("writing Databricks-side feeds ...")
qh.repartition(8).write.mode("overwrite").json(f"{VOL}/query_history/")
lin.repartition(4).write.mode("overwrite").json(f"{VOL}/table_lineage/")
aud.repartition(8).write.mode("overwrite").json(f"{VOL}/uc_audit/")
print("writing external feeds ...")
ts_str(idp_all, "published").repartition(4).write.mode("overwrite").json(f"{VOL}/idp/")
ts_str(ep_all, "timestamp").repartition(2).write.mode("overwrite").json(f"{VOL}/endpoint/")
ts_str(dlp_all, "timestamp").repartition(2).write.mode("overwrite").json(f"{VOL}/dlp/")

print("writing business context ...")
emp_df.drop("user_idx", "office_ip").coalesce(1).write.mode("overwrite").option("header", True).csv(f"{VOL}/hr/")
spark.createDataFrame(devices, dev_schema).coalesce(1).write.mode("overwrite").option("header", True).csv(f"{VOL}/devices/")
assets = [
    (HOLDINGS, f"{FQ}.portfolio_fund_holdings", "confidential", 2, "Daily positions and weights per fund (non-public until disclosed)", "Routine portfolio and fund reporting", "SEC Rule 204-2; holdings disclosure policy", "Portfolio Management;Compliance;Equity Research;Trading"),
    (RATINGS, f"{FQ}.research_unpublished_ratings", "restricted", 3, "Rating changes, price targets and estimate revisions before publication", "Research publishing workflow", "FINRA 2241; Reg FD", "Equity Research;Compliance;Portfolio Management"),
    (ORDERS, f"{FQ}.trading_pending_block_orders", "highly_restricted", 4, "Block orders not yet executed", "Trading desk execution only", "MNPI; Reg NMS", "Trading"),
    (CRM, f"{FQ}.crm_client_relationships", "internal", 1, "Institutional client relationships", "Client relationship management", None, "Client Service;Portfolio Management;Compliance"),
    (WEB, f"{FQ}.analytics_web_sessions", "internal", 1, "Web analytics", "Product analytics", None, "Engineering;IT;HR;Legal;Client Service"),
]
spark.createDataFrame(assets, "asset_full_name string, physical_table string, sensitivity string, sensitivity_rank int, content string, expected_use string, regulation string, granted_departments string") \
    .coalesce(1).write.mode("overwrite").json(f"{VOL}/assets/")
workflows = [
    ("WF-01", "Portfolio and fund reporting", HOLDINGS, "Portfolio Management;Compliance;Equity Research;Trading", "Business hours, any business day"),
    ("WF-02", "Research publishing", RATINGS, "Equity Research", "Business hours; via the research management system"),
    ("WF-03", "Research surveillance review", RATINGS, "Compliance", "Business hours; requires exception ticket for bulk extracts"),
    ("WF-04", "Block trade execution", ORDERS, "Trading", "Market hours; trading desk only"),
    ("WF-05", "Client relationship reporting", CRM, "Client Service;Portfolio Management;Compliance", "Any"),
    ("WF-06", "Product analytics", WEB, "Engineering;IT;HR;Legal;Client Service", "Any"),
]
spark.createDataFrame(workflows, "workflow_id string, workflow_name string, asset_full_name string, approved_departments string, conditions string") \
    .coalesce(1).write.mode("overwrite").json(f"{VOL}/workflows/")
exceptions = [
    ("EXC-4471", PRIYA[1], RATINGS, "Q3 research-publication surveillance review - full extract approved by CCO", "2026-09-28", "2026-09-30", "approved", "Chief Compliance Officer (E-0090)"),
    ("EXC-4302", EMP_IDX[60][1], HOLDINGS, "Quarterly holdings disclosure preparation", "2026-08-25", "2026-08-29", "approved", "Head of Portfolio Analytics (E-0045)"),
]
spark.createDataFrame(exceptions, "ticket_id string, employee_id string, asset_full_name string, justification string, valid_from string, valid_to string, status string, approver string") \
    .coalesce(1).write.mode("overwrite").json(f"{VOL}/exceptions/")
spark.createDataFrame(calendar_rows, "cal_date string, is_business_day boolean, is_close_period boolean, period_label string") \
    .coalesce(1).write.mode("overwrite").option("header", True).csv(f"{VOL}/calendar/")

# ---------------------------------------------------------------------------
# Physical stand-ins for the governed investment assets (real UC tables)
# ---------------------------------------------------------------------------
print("writing governed business tables ...")
FUNDS = ["Harborview Growth Fund", "Harborview Income Builder", "Harborview Global Equity", "Harborview Core Bond",
         "Harborview Emerging Markets", "Harborview Balanced Target 2045"]
TICKERS = ["AAPL", "MSFT", "NVDA", "AMZN", "GOOGL", "META", "JPM", "V", "UNH", "XOM", "LLY", "AVGO", "TSM", "ASML", "NESN", "SAP"]


def pick(values, mod_col):
    return F.element_at(F.array(*[F.lit(x) for x in values]), (mod_col % len(values) + 1).cast("int"))


spark.range(0, 2400).select(
    pick(FUNDS, F.col("id")).alias("fund_name"),
    F.expr("date_add(date'2026-09-01', cast(id % 30 as int))").alias("as_of_date"),
    pick(TICKERS, F.col("id")).alias("ticker"),
    pick(["Equity", "Equity", "Equity", "Fixed Income", "Cash"], F.col("id")).alias("asset_class"),
    F.round(F.rand(1) * 5_000_000, 0).alias("shares"), F.round(F.rand(2) * 900_000_000, 2).alias("market_value_usd"),
    F.round(F.rand(3) * 6, 3).alias("weight_pct"),
).write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}.portfolio_fund_holdings")
spark.range(0, 6000).select(
    F.concat(F.lit("RR-"), F.lpad(F.col("id").cast("string"), 6, "0")).alias("rating_id"),
    pick(TICKERS, F.col("id")).alias("ticker"),
    pick(["Technology", "Financials", "Health Care", "Energy", "Consumer", "Industrials"], F.col("id")).alias("sector"),
    F.concat(F.lit("E-0"), (F.col("id") % 20 + 110).cast("string")).alias("analyst_id"),
    pick(["Buy", "Hold", "Sell"], F.col("id")).alias("current_rating"),
    pick(["Buy", "Hold", "Sell"], F.col("id") + 1).alias("new_rating"),
    F.round(F.rand(4) * 400 + 20, 2).alias("current_price_target"), F.round(F.rand(5) * 400 + 20, 2).alias("new_price_target"),
    F.round(F.randn(6) * 8, 1).alias("eps_revision_pct"),
    F.expr("date_add(date'2026-10-01', cast(id % 45 as int))").alias("planned_publish_date"),
    pick(["Draft", "Pending compliance review", "Scheduled"], F.col("id")).alias("status"),
).write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}.research_unpublished_ratings")
spark.range(0, 180).select(
    F.concat(F.lit("BLK-"), F.lpad(F.col("id").cast("string"), 5, "0")).alias("order_id"),
    pick(FUNDS, F.col("id")).alias("fund_name"),
    pick(TICKERS, F.col("id")).alias("ticker"),
    pick(["BUY", "SELL"], F.col("id")).alias("side"),
    F.round(F.rand(7) * 3_000_000 + 100_000, 0).alias("shares"), F.round(F.rand(8) * 400 + 20, 2).alias("limit_price"),
    pick(["Equity", "Fixed Income"], F.col("id")).alias("desk"),
    pick(["Staged", "Working"], F.col("id")).alias("status"),
).write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}.trading_pending_block_orders")
spark.range(0, 3000).select(F.concat(F.lit("REL-"), F.col("id").cast("string")).alias("relationship_id"),
    pick(["Pension", "Endowment", "Sovereign", "Insurance"], F.col("id")).alias("client_segment"),
    F.round(F.rand(9) * 5e9, 0).alias("aum_usd"), pick(["Prospect", "Onboarding", "Active"], F.col("id")).alias("stage")) \
    .write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}.crm_client_relationships")
spark.range(0, 5000).select(F.concat(F.lit("WS-"), F.col("id").cast("string")).alias("session_id"),
    F.expr("date_add(date'2026-07-01', cast(id % 90 as int))").alias("session_date"), (F.rand(8) * 600).cast("int").alias("duration_s")) \
    .write.mode("overwrite").option("overwriteSchema", True).saveAsTable(f"{FQ}.analytics_web_sessions")

for t in ["_gen_user_days", "_gen_queries"]:
    spark.sql(f"DROP TABLE IF EXISTS {FQ}.{t}")
print("DONE")
for sub, fmt in [("query_history", "json"), ("uc_audit", "json"), ("table_lineage", "json"), ("idp", "json"), ("endpoint", "json"), ("dlp", "json"), ("hr", "csv"), ("devices", "csv")]:
    print(sub, spark.read.format(fmt).option("header", True).load(f"{VOL}/{sub}/").count())

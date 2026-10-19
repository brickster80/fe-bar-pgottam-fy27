# Databricks notebook source
# MAGIC %md
# MAGIC # Q2 - Was the access unusual for that employee and their peers?
# MAGIC
# MAGIC Unsupervised **Isolation Forest** over `gold_user_daily_features` (identity, Databricks data access,
# MAGIC endpoint and DLP signals per employee-day). Registered in Unity Catalog (`@prod`); every score is explained
# MAGIC by the features that deviate most from the employee's department peers.

# COMMAND ----------

dbutils.widgets.text("catalog", "capmarkets_stg")
dbutils.widgets.text("schema", "febar_e2e")
CATALOG, SCHEMA = dbutils.widgets.get("catalog"), dbutils.widgets.get("schema")
FQ = f"{CATALOG}.{SCHEMA}"

import json
import mlflow
import mlflow.sklearn
import numpy as np
from mlflow.tracking import MlflowClient
from sklearn.ensemble import IsolationForest
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

mlflow.set_registry_uri("databricks-uc")
user = spark.sql("SELECT current_user()").first()[0]
mlflow.set_experiment(f"/Users/{user}/febar_e2e_access_anomaly")
client = MlflowClient(registry_uri="databricks-uc")

FEATURES = [
    "signins", "unassigned_device_signins", "new_device_signins", "off_hours_signins",
    "sensitive_statements", "rows_returned", "max_sensitivity_rank", "off_hours_sensitive_statements", "client_apps",
    "max_ratio_vs_self", "max_ratio_vs_peers", "first_access_restricted",
    "files_created", "file_bytes", "personal_uploads", "personal_upload_bytes", "sensitive_personal_uploads",
]
LOG_FEATURES = ["rows_returned", "max_ratio_vs_self", "max_ratio_vs_peers", "file_bytes", "personal_upload_bytes"]
ID_COLS = ["feature_id", "employee_id", "full_name", "department", "role", "activity_date"]

# COMMAND ----------

pdf = spark.table(f"{FQ}.gold_user_daily_features").toPandas()
X = pdf[FEATURES].fillna(0).astype(float)
for c in LOG_FEATURES:
    X[c] = np.log1p(X[c])

CONTAMINATION = 0.005
model = Pipeline([("scaler", StandardScaler()),
                  ("iso", IsolationForest(n_estimators=300, contamination=CONTAMINATION, random_state=7))])
model_name = f"{FQ}.access_movement_iforest"
with mlflow.start_run(run_name="access_movement_iforest"):
    model.fit(X)
    raw = -model.named_steps["iso"].score_samples(model.named_steps["scaler"].transform(X))
    score = (raw - raw.min()) / (raw.max() - raw.min() + 1e-9)
    pred = model.predict(X)
    mlflow.log_params({"n_features": len(FEATURES), "contamination": CONTAMINATION, "n_estimators": 300})
    mlflow.log_metrics({"rows": len(X), "flagged": int((pred == -1).sum())})
    info = mlflow.sklearn.log_model(model, name="model", signature=mlflow.models.infer_signature(X, pred),
                                    serialization_format="cloudpickle", input_example=X.head(3),
                                    registered_model_name=model_name)
client.set_registered_model_alias(model_name, "prod", info.registered_model_version)

# COMMAND ----------

# Explain each score vs. department peers (robust z-score on the raw features)
raw_X = pdf[FEATURES].fillna(0).astype(float)
grp = raw_X.groupby(pdf["department"])
med = grp.transform("median")
mad = grp.transform(lambda s: (s - s.median()).abs().median())
z = ((raw_X - med) / (1.4826 * mad.replace(0, np.nan))).fillna((raw_X - med) / raw_X.std(ddof=0).replace(0, 1))
z = z.clip(lower=0)


def drivers(row):
    top = row.sort_values(ascending=False).head(3)
    return [f"{k} ({row[k]:.0f}x peer spread)" if row[k] < 1000 else f"{k} (extreme vs peers)" for k in top.index if row[k] > 3]


out = pdf[ID_COLS].copy()
out["anomaly_score"] = np.round(score, 4)
out["is_anomaly"] = pred == -1
out["top_drivers"] = z.apply(drivers, axis=1)
for c in ["rows_returned", "max_ratio_vs_self", "max_ratio_vs_peers", "unassigned_device_signins", "personal_upload_bytes"]:
    out[c] = pdf[c]
(spark.createDataFrame(out).write.mode("overwrite").option("overwriteSchema", "true")
 .saveAsTable(f"{FQ}.gold_user_day_anomaly"))
spark.sql(f"COMMENT ON TABLE {FQ}.gold_user_day_anomaly IS 'ML: Isolation Forest anomaly per employee-day ({model_name}@prod) with peer-relative drivers'")
dbutils.notebook.exit(json.dumps({"model": model_name, "version": info.registered_model_version, "flagged": int(out["is_anomaly"].sum())}))

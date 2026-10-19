CREATE OR REFRESH MATERIALIZED VIEW silver_calendar
COMMENT 'Reporting calendar incl. month-end close periods'
TBLPROPERTIES ('quality' = 'silver')
AS SELECT cast(cal_date AS DATE) AS cal_date, cast(is_business_day AS BOOLEAN) AS is_business_day,
  cast(is_close_period AS BOOLEAN) AS is_close_period, period_label
FROM bronze_calendar
QUALIFY row_number() OVER (PARTITION BY cal_date ORDER BY _ingested_at DESC) = 1;

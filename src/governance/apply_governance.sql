-- =====================================================================
-- Unity Catalog governance: "Authorized access, unauthorized movement" (idempotent)
-- Physical stand-ins for finance_prod.* governed assets live in capmarkets_stg.febar_e2e
-- =====================================================================
CREATE TABLE IF NOT EXISTS capmarkets_stg.febar_e2e.gov_access_policy (
  principal           STRING  COMMENT 'User email or service principal application id',
  can_view_bank_details BOOLEAN COMMENT 'Unmask vendor routing / account numbers (treasury workflow)',
  can_view_forecast   BOOLEAN COMMENT 'See acquisition forecast rows (corporate development deal team)'
) COMMENT 'Fine-grained access policy mapping used by UC column masks and row filters';

MERGE INTO capmarkets_stg.febar_e2e.gov_access_policy t
USING (SELECT current_user() AS principal, false AS can_view_bank_details, false AS can_view_forecast) s
ON t.principal = s.principal WHEN NOT MATCHED THEN INSERT *;

CREATE OR REPLACE FUNCTION capmarkets_stg.febar_e2e.mask_bank_number(v STRING)
RETURNS STRING
COMMENT 'Column mask: full routing/account number only for approved treasury workflows'
RETURN CASE WHEN is_account_group_member('febar_treasury_ops')
              OR EXISTS (SELECT 1 FROM capmarkets_stg.febar_e2e.gov_access_policy p WHERE p.principal = current_user() AND p.can_view_bank_details)
            THEN v ELSE concat(repeat('*', greatest(length(v) - 4, 0)), right(v, 4)) END;

CREATE OR REPLACE FUNCTION capmarkets_stg.febar_e2e.filter_forecast(stage STRING)
RETURNS BOOLEAN
COMMENT 'Row filter: acquisition forecast visible only to the corporate-development deal team'
RETURN is_account_group_member('febar_corpdev_deal_team')
    OR EXISTS (SELECT 1 FROM capmarkets_stg.febar_e2e.gov_access_policy p WHERE p.principal = current_user() AND p.can_view_forecast);

COMMENT ON TABLE capmarkets_stg.febar_e2e.reporting_monthly_summary IS 'Stand-in for finance_prod.reporting.monthly_summary - aggregated financial results; routine analyst reporting.';
COMMENT ON TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts IS 'Stand-in for finance_prod.treasury.vendor_bank_accounts - vendor bank-account information; approved treasury workflows only.';
COMMENT ON TABLE capmarkets_stg.febar_e2e.strategy_acquisition_forecast IS 'Stand-in for finance_prod.strategy.acquisition_forecast - confidential acquisition forecasts (MNPI); corporate development only.';

ALTER TABLE capmarkets_stg.febar_e2e.reporting_monthly_summary     SET TAGS ('classification' = 'confidential',      'regulation' = 'SOX',             'domain' = 'finance', 'logical_asset' = 'finance_prod.reporting.monthly_summary');
ALTER TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts SET TAGS ('classification' = 'restricted',        'regulation' = 'SOX;PCI-adjacent', 'domain' = 'finance', 'logical_asset' = 'finance_prod.treasury.vendor_bank_accounts');
ALTER TABLE capmarkets_stg.febar_e2e.strategy_acquisition_forecast SET TAGS ('classification' = 'highly_restricted', 'regulation' = 'MNPI',            'domain' = 'finance', 'logical_asset' = 'finance_prod.strategy.acquisition_forecast');
ALTER TABLE capmarkets_stg.febar_e2e.sales_crm_opportunities       SET TAGS ('classification' = 'internal', 'domain' = 'CRM');
ALTER TABLE capmarkets_stg.febar_e2e.analytics_web_sessions        SET TAGS ('classification' = 'internal');

ALTER TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts ALTER COLUMN routing_number SET TAGS ('sensitive_field' = 'bank_routing_number');
ALTER TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts ALTER COLUMN account_number SET TAGS ('sensitive_field' = 'bank_account_number');
ALTER TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts ALTER COLUMN routing_number SET MASK capmarkets_stg.febar_e2e.mask_bank_number;
ALTER TABLE capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts ALTER COLUMN account_number SET MASK capmarkets_stg.febar_e2e.mask_bank_number;
ALTER TABLE capmarkets_stg.febar_e2e.strategy_acquisition_forecast SET ROW FILTER capmarkets_stg.febar_e2e.filter_forecast ON (stage);

-- ---------- LIVE Databricks evidence from real system tables (scoped to the governed stand-ins) ----------
CREATE OR REPLACE VIEW capmarkets_stg.febar_e2e.v_live_audit_governed
COMMENT 'LIVE system.access.audit: who touched the governed financial stand-ins in this schema (last 7 days)'
AS SELECT event_time, user_identity.email AS user_email, service_name, action_name,
          coalesce(request_params.full_name_arg, request_params.table_full_name) AS table_full_name,
          source_ip_address, user_agent, response.status_code AS status_code
FROM system.access.audit
WHERE event_date >= current_date() - 7
  AND service_name = 'unityCatalog'
  AND action_name IN ('getTable', 'generateTemporaryTableCredential', 'getTablePermissions')
  AND coalesce(request_params.full_name_arg, request_params.table_full_name) IN (
      'capmarkets_stg.febar_e2e.reporting_monthly_summary', 'capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts', 'capmarkets_stg.febar_e2e.strategy_acquisition_forecast');

CREATE OR REPLACE VIEW capmarkets_stg.febar_e2e.v_live_lineage_governed
COMMENT 'LIVE system.access.table_lineage: statements and entities that read the governed financial stand-ins (last 7 days)'
AS SELECT event_time, created_by, entity_type, entity_id, statement_id, source_table_full_name, target_table_full_name
FROM system.access.table_lineage
WHERE event_date >= current_date() - 7
  AND source_table_full_name IN ('capmarkets_stg.febar_e2e.reporting_monthly_summary', 'capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts', 'capmarkets_stg.febar_e2e.strategy_acquisition_forecast');

CREATE OR REPLACE VIEW capmarkets_stg.febar_e2e.v_live_query_evidence
COMMENT 'LIVE system.query.history joined to lineage: query execution evidence for reads of the governed financial stand-ins'
AS SELECT q.statement_id, q.executed_by, q.start_time, q.end_time, q.execution_status, q.client_application,
          q.produced_rows, q.read_bytes, q.total_duration_ms, l.source_table_full_name, left(q.statement_text, 300) AS statement_text
FROM system.query.history q
JOIN capmarkets_stg.febar_e2e.v_live_lineage_governed l ON q.statement_id = l.statement_id
WHERE q.start_time >= current_date() - 7;

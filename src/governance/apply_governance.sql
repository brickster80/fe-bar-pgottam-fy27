-- =====================================================================
-- Unity Catalog governance: "Authorized access, unauthorized movement" (idempotent)
-- Harborview Investment Management. Physical stand-ins for invest_prod.* governed assets live in capmarkets_stg.febar_e2e
-- =====================================================================
CREATE TABLE IF NOT EXISTS capmarkets_stg.febar_e2e.gov_access_policy (
  principal                STRING  COMMENT 'User email or service principal application id',
  can_view_unpublished     BOOLEAN COMMENT 'See pre-publication ratings and price targets (research publishing workflow)',
  can_view_block_orders    BOOLEAN COMMENT 'See pending block orders (trading desk)'
) COMMENT 'Fine-grained access policy mapping used by UC column masks and row filters';

MERGE INTO capmarkets_stg.febar_e2e.gov_access_policy t
USING (SELECT current_user() AS principal, false AS can_view_unpublished, false AS can_view_block_orders) s
ON t.principal = s.principal WHEN NOT MATCHED THEN INSERT *;

CREATE OR REPLACE FUNCTION capmarkets_stg.febar_e2e.mask_unpublished_rating(v STRING)
RETURNS STRING
COMMENT 'Column mask: the pre-publication rating is visible only inside the research publishing workflow'
RETURN CASE WHEN is_account_group_member('febar_research_publishing')
              OR EXISTS (SELECT 1 FROM capmarkets_stg.febar_e2e.gov_access_policy p WHERE p.principal = current_user() AND p.can_view_unpublished)
            THEN v ELSE '** pre-publication **' END;

CREATE OR REPLACE FUNCTION capmarkets_stg.febar_e2e.mask_price_target(v DOUBLE)
RETURNS DOUBLE
COMMENT 'Column mask: the pre-publication price target is NULL outside the research publishing workflow'
RETURN CASE WHEN is_account_group_member('febar_research_publishing')
              OR EXISTS (SELECT 1 FROM capmarkets_stg.febar_e2e.gov_access_policy p WHERE p.principal = current_user() AND p.can_view_unpublished)
            THEN v ELSE NULL END;

CREATE OR REPLACE FUNCTION capmarkets_stg.febar_e2e.filter_block_orders(desk STRING)
RETURNS BOOLEAN
COMMENT 'Row filter: pending block orders (MNPI) visible only to the trading desk'
RETURN is_account_group_member('febar_trading_desk')
    OR EXISTS (SELECT 1 FROM capmarkets_stg.febar_e2e.gov_access_policy p WHERE p.principal = current_user() AND p.can_view_block_orders);

COMMENT ON TABLE capmarkets_stg.febar_e2e.portfolio_fund_holdings IS 'Stand-in for invest_prod.portfolio.fund_holdings - daily positions and weights per fund (non-public until disclosed); routine portfolio and fund reporting.';
COMMENT ON TABLE capmarkets_stg.febar_e2e.research_unpublished_ratings IS 'Stand-in for invest_prod.research.unpublished_ratings - rating changes, price targets and estimate revisions before publication; research publishing workflow only (FINRA 2241, Reg FD).';
COMMENT ON TABLE capmarkets_stg.febar_e2e.trading_pending_block_orders IS 'Stand-in for invest_prod.trading.pending_block_orders - block orders not yet executed (MNPI); trading desk only.';

ALTER TABLE capmarkets_stg.febar_e2e.portfolio_fund_holdings      SET TAGS ('classification' = 'confidential',      'regulation' = 'SEC Rule 204-2', 'domain' = 'finance', 'logical_asset' = 'invest_prod.portfolio.fund_holdings');
ALTER TABLE capmarkets_stg.febar_e2e.research_unpublished_ratings SET TAGS ('classification' = 'restricted',        'regulation' = 'FINRA 2241;Reg FD', 'domain' = 'finance', 'logical_asset' = 'invest_prod.research.unpublished_ratings');
ALTER TABLE capmarkets_stg.febar_e2e.trading_pending_block_orders SET TAGS ('classification' = 'highly_restricted', 'regulation' = 'MNPI;Reg NMS',    'domain' = 'finance', 'logical_asset' = 'invest_prod.trading.pending_block_orders');
ALTER TABLE capmarkets_stg.febar_e2e.crm_client_relationships     SET TAGS ('classification' = 'internal', 'domain' = 'CRM');
ALTER TABLE capmarkets_stg.febar_e2e.analytics_web_sessions       SET TAGS ('classification' = 'internal');

ALTER TABLE capmarkets_stg.febar_e2e.research_unpublished_ratings ALTER COLUMN new_rating SET TAGS ('sensitive_field' = 'unpublished_rating');
ALTER TABLE capmarkets_stg.febar_e2e.research_unpublished_ratings ALTER COLUMN new_price_target SET TAGS ('sensitive_field' = 'unpublished_price_target');
ALTER TABLE capmarkets_stg.febar_e2e.research_unpublished_ratings ALTER COLUMN new_rating SET MASK capmarkets_stg.febar_e2e.mask_unpublished_rating;
ALTER TABLE capmarkets_stg.febar_e2e.research_unpublished_ratings ALTER COLUMN new_price_target SET MASK capmarkets_stg.febar_e2e.mask_price_target;
ALTER TABLE capmarkets_stg.febar_e2e.trading_pending_block_orders SET ROW FILTER capmarkets_stg.febar_e2e.filter_block_orders ON (desk);

-- ---------- LIVE Databricks evidence from real system tables (scoped to the governed stand-ins) ----------
CREATE OR REPLACE VIEW capmarkets_stg.febar_e2e.v_live_audit_governed
COMMENT 'LIVE system.access.audit: who touched the governed investment stand-ins in this schema (last 7 days)'
AS SELECT event_time, user_identity.email AS user_email, service_name, action_name,
          coalesce(request_params.full_name_arg, request_params.table_full_name) AS table_full_name,
          source_ip_address, user_agent, response.status_code AS status_code
FROM system.access.audit
WHERE event_date >= current_date() - 7
  AND service_name = 'unityCatalog'
  AND action_name IN ('getTable', 'generateTemporaryTableCredential', 'getTablePermissions')
  AND coalesce(request_params.full_name_arg, request_params.table_full_name) IN (
      'capmarkets_stg.febar_e2e.portfolio_fund_holdings', 'capmarkets_stg.febar_e2e.research_unpublished_ratings', 'capmarkets_stg.febar_e2e.trading_pending_block_orders');

CREATE OR REPLACE VIEW capmarkets_stg.febar_e2e.v_live_lineage_governed
COMMENT 'LIVE system.access.table_lineage: statements and entities that read the governed investment stand-ins (last 7 days)'
AS SELECT event_time, created_by, entity_type, entity_id, statement_id, source_table_full_name, target_table_full_name
FROM system.access.table_lineage
WHERE event_date >= current_date() - 7
  AND source_table_full_name IN ('capmarkets_stg.febar_e2e.portfolio_fund_holdings', 'capmarkets_stg.febar_e2e.research_unpublished_ratings', 'capmarkets_stg.febar_e2e.trading_pending_block_orders');

CREATE OR REPLACE VIEW capmarkets_stg.febar_e2e.v_live_query_evidence
COMMENT 'LIVE system.query.history joined to lineage: query execution evidence for reads of the governed investment stand-ins'
AS SELECT q.statement_id, q.executed_by, q.start_time, q.end_time, q.execution_status, q.client_application,
          q.produced_rows, q.read_bytes, q.total_duration_ms, l.source_table_full_name, left(q.statement_text, 300) AS statement_text
FROM system.query.history q
JOIN capmarkets_stg.febar_e2e.v_live_lineage_governed l ON q.statement_id = l.statement_id
WHERE q.start_time >= current_date() - 7;

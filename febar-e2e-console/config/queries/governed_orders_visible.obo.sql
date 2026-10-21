-- Runs AS THE SIGNED-IN USER: UC row filter decides whether any pending block orders (MNPI) are visible
SELECT count(*) AS visible_rows, count(DISTINCT fund_name) AS visible_funds
FROM capmarkets_stg.febar_e2e.trading_pending_block_orders

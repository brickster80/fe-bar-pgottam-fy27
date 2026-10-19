-- Runs AS THE SIGNED-IN USER: UC column masks decide what routing / account numbers look like
SELECT vendor_id, vendor_name, bank_name, routing_number, account_number, country
FROM capmarkets_stg.febar_e2e.treasury_vendor_bank_accounts
ORDER BY ytd_payments_usd DESC
LIMIT 6

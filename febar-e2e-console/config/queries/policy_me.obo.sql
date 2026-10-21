SELECT current_user() AS principal,
       coalesce(max(can_view_unpublished), false) AS can_view_unpublished,
       coalesce(max(can_view_block_orders), false) AS can_view_block_orders
FROM capmarkets_stg.febar_e2e.gov_access_policy WHERE principal = current_user()

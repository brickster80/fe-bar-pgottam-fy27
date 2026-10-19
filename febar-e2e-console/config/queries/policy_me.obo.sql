SELECT current_user() AS principal,
       coalesce(max(can_view_bank_details), false) AS can_view_bank_details,
       coalesce(max(can_view_forecast), false) AS can_view_forecast
FROM capmarkets_stg.febar_e2e.gov_access_policy WHERE principal = current_user()

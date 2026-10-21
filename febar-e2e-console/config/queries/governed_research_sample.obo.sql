-- Runs AS THE SIGNED-IN USER: UC column masks decide whether pre-publication ratings and price targets are visible
SELECT rating_id, ticker, sector, current_rating, new_rating, current_price_target, new_price_target, planned_publish_date, status
FROM capmarkets_stg.febar_e2e.research_unpublished_ratings
ORDER BY planned_publish_date, rating_id
LIMIT 6

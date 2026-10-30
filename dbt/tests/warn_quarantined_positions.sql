{{ config(severity = 'warn') }}
-- WARNS when any position was withheld from Gold because of a missing / stale price.
select portfolio_id, security_id, pricing_status, price_date, price_age_days
from {{ ref('silver_priced_positions') }}
where pricing_status in ('MISSING_PRICE', 'STALE_PRICE')

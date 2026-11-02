-- =============================================================================
-- SILVER :  matches positions to the best available price and determines whether that price is current, stale, or missing.
-- Decides the PRICING outcome of every accepted position:
--   CURRENT       price dated on the position date
--   STALE_WARN    price 1..max_price_stale_days old   -> published, flagged
--   STALE_PRICE   price older than the limit          -> QUARANTINED (not published)
--   MISSING_PRICE no usable price at all              -> QUARANTINED (not published)
-- Gold publishes only CURRENT + STALE_WARN. Quarantined rows are reported, never dropped.
-- =============================================================================

-- STEP 1: accepted positions for the business date only (business-date reruns)
with pos as (
    select *
    from {{ ref('silver_positions') }}
    where dq_status = 'ACCEPTED'
      and position_date = '{{ var("business_date") }}'::date
),

-- STEP 2: pick ONE price per position:
--   * only accepted prices, same currency, dated on/before the position date
--   * newest price_date first; if two vendors tie, VENDOR_A beats VENDOR_B
priced as (
    select
        pos.portfolio_id, pos.security_id, pos.position_date, pos.quantity, pos.book_value,
        pos.currency, pos.isin_at_date as isin, pos.asset_class,
        pos._source_file as position_source_file, pos._source_row as position_source_row,
        pr.price, pr.price_date, pr.price_source,
        pr._source_file as price_source_file, pr._source_row as price_source_row,
        datediff('day', pr.price_date, pos.position_date) as price_age_days
    from pos
    left join {{ ref('silver_market_prices') }} pr
        on  pr.dq_status = 'ACCEPTED'
        and pr.security_id = pos.security_id
        and pr.price_currency = pos.currency
        and pr.price_date <= pos.position_date
    qualify row_number() over (
        partition by pos.portfolio_id, pos.security_id, pos.position_date
        order by pr.price_date desc nulls last,
                 case pr.price_source when 'VENDOR_A' then 1 when 'VENDOR_B' then 2 else 9 end
    ) = 1
)

-- STEP 3: classify
select
    *,
    case
        when price is null                                          then 'MISSING_PRICE'
        when price_age_days > {{ var('max_price_stale_days') }}     then 'STALE_PRICE'
        when price_age_days > 0                                     then 'STALE_WARN'
        else 'CURRENT'
    end as pricing_status
from priced

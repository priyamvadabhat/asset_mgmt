-- =============================================================================
-- SILVER : market prices
-- Rules: missing key, invalid/future date, price <= 0 or non-numeric,
--        missing currency/source, unknown security, currency mismatch, duplicates.
-- Note: two vendors may quote the same security/day - both are KEPT here
--       (key includes price_source). The vendor choice is made in Gold.
-- =============================================================================

-- STEP 1: type / clean
with parsed as (
    select
        nullif(trim(security_id), '')           as security_id,
        try_to_date(nullif(trim(price_date), '')) as price_date,
        try_to_number(nullif(trim(price), ''), 38, 6) as price,        -- 'abc' -> NULL
        upper(nullif(trim(price_currency), '')) as price_currency,
        upper(nullif(trim(price_source), ''))   as price_source,
        _source_file, _source_row, _loaded_at,
        object_construct(*)                     as raw_record
    from {{ source('raw', 'market_prices') }}
),

-- STEP 2: temporal join - security master valid ON THE PRICE DATE
joined as (
    select
        p.*,
        sm.currency as security_currency,
        sm.isin     as isin_at_price_date
    from parsed p
    left join {{ ref('silver_security_master') }} sm
        on  sm.dq_status = 'ACCEPTED'
        and sm.security_id = p.security_id
        and p.price_date >= sm.effective_from
        and (sm.effective_to is null or p.price_date <= sm.effective_to)
),

-- STEP 3: duplicates + validation
checked as (
    select
        *,
        row_number() over (
            partition by coalesce(security_id, _source_file || '-' || _source_row::varchar), price_date, price_source
            order by _loaded_at desc, _source_file desc, _source_row desc
        ) as rn,
        array_to_string(array_construct_compact(
            iff(security_id is null,                            'MISSING_SECURITY_ID', null),
            iff(price_date is null,                             'INVALID_PRICE_DATE', null),
            iff(price_date > '{{ var("business_date") }}'::date,'FUTURE_PRICE_DATE', null),
            iff(price is null or price <= 0,                    'INVALID_PRICE', null),   -- catches the 0 price
            iff(price_currency is null,                         'MISSING_PRICE_CURRENCY', null),
            iff(price_source is null,                           'MISSING_PRICE_SOURCE', null),
            iff(security_id is not null and price_date is not null and isin_at_price_date is null,
                                                                'UNKNOWN_SECURITY', null),
            iff(security_currency is not null and price_currency is distinct from security_currency,
                                                                'CURRENCY_MISMATCH', null)
        ), ',') as reject_reasons
    from joined
)

select
    *,
    case when rn > 1 then 'DUPLICATE'
         when reject_reasons <> '' then 'REJECTED'
         else 'ACCEPTED' end as dq_status
from checked

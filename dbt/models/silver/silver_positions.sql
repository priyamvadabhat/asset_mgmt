-- =============================================================================
-- SILVER : positions (reported holdings snapshot)
-- Rules: missing keys, invalid/future date, non-numeric quantity/book value,
--        unknown security on position_date, currency mismatch, duplicates.
-- =============================================================================

-- STEP 1: type / clean
with parsed as (
    select
        nullif(trim(portfolio_id), '')          as portfolio_id,
        nullif(trim(security_id), '')           as security_id,
        try_to_date(nullif(trim(position_date), '')) as position_date,
        try_to_number(nullif(trim(quantity), ''), 38, 6)   as quantity,
        try_to_number(nullif(trim(book_value), ''), 38, 4) as book_value,
        upper(nullif(trim(currency), ''))       as currency,
        _source_file, _source_row, _loaded_at,
        object_construct(*)                     as raw_record
    from {{ source('raw', 'positions') }}
),

-- STEP 2: temporal join - security master version valid ON THE POSITION DATE
joined as (
    select
        p.*,
        sm.isin       as isin_at_date,
        sm.asset_class,
        sm.currency   as security_currency
    from parsed p
    left join {{ ref('silver_security_master') }} sm
        on  sm.dq_status = 'ACCEPTED'
        and sm.security_id = p.security_id
        and p.position_date >= sm.effective_from
        and (sm.effective_to is null or p.position_date <= sm.effective_to)
),

-- STEP 3: duplicates + validation
checked as (
    select
        *,
        -- Business key = portfolio + security + date. Latest delivery wins.
        row_number() over (
            partition by coalesce(portfolio_id, _source_file || '-' || _source_row::varchar), security_id, position_date
            order by _loaded_at desc, _source_file desc, _source_row desc
        ) as rn,
        array_to_string(array_construct_compact(
            iff(portfolio_id is null,                           'MISSING_PORTFOLIO_ID', null),
            iff(security_id is null,                            'MISSING_SECURITY_ID', null),
            iff(position_date is null,                          'INVALID_POSITION_DATE', null),
            iff(position_date > '{{ var("business_date") }}'::date, 'FUTURE_POSITION_DATE', null),
            iff(quantity is null,                               'INVALID_QUANTITY', null),
            iff(book_value is null,                             'INVALID_BOOK_VALUE', null),
            iff(security_id is not null and position_date is not null and isin_at_date is null,
                                                                'UNKNOWN_SECURITY', null),
            iff(isin_at_date is not null and currency is distinct from security_currency,
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

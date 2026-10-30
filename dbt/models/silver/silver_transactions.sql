-- =============================================================================
-- SILVER : transactions
-- Rules: missing keys, invalid/future date, bad quantity/price, bad txn_type,
--        unknown security (effective-dated lookup on trade_date),
--        currency mismatch, duplicate transaction_id.
-- Idempotency: de-duplicated on transaction_id (latest delivery wins), so
--        re-delivering a file can never double count a trade.
-- =============================================================================

-- STEP 1: type / clean the raw strings
with parsed as (
    select
        nullif(trim(transaction_id), '')        as transaction_id,
        nullif(trim(portfolio_id), '')          as portfolio_id,
        nullif(trim(security_id), '')           as security_id,
        try_to_date(nullif(trim(trade_date), '')) as trade_date,       -- '2026-02-30' -> NULL
        upper(nullif(trim(txn_type), ''))       as txn_type,
        try_to_number(nullif(trim(quantity), ''), 38, 6) as quantity,  -- 'abc' -> NULL
        try_to_number(nullif(trim(price), ''), 38, 6)    as price,
        upper(nullif(trim(currency), ''))       as currency,
        _source_file, _source_row, _loaded_at,
        object_construct(*)                     as raw_record
    from {{ source('raw', 'transactions') }}
),

-- STEP 2: temporal join - the security master row that was valid ON THE TRADE DATE
joined as (
    select
        p.*,
        sm.isin     as isin_at_trade,
        sm.currency as security_currency
    from parsed p
    left join {{ ref('silver_security_master') }} sm
        on  sm.dq_status = 'ACCEPTED'
        and sm.security_id = p.security_id
        and p.trade_date >= sm.effective_from
        and (sm.effective_to is null or p.trade_date <= sm.effective_to)
),

-- STEP 3: duplicate detection + validation rules
checked as (
    select
        *,
        -- Business key = transaction_id. Latest delivery wins (supports corrected records).
        row_number() over (
            partition by coalesce(transaction_id, _source_file || '-' || _source_row::varchar)
            order by _loaded_at desc, _source_file desc, _source_row desc
        ) as rn,
        array_to_string(array_construct_compact(
            iff(transaction_id is null,                         'MISSING_TRANSACTION_ID', null),
            iff(portfolio_id is null,                           'MISSING_PORTFOLIO_ID', null),
            iff(security_id is null,                            'MISSING_SECURITY_ID', null),
            iff(trade_date is null,                             'INVALID_TRADE_DATE', null),
            iff(trade_date > '{{ var("business_date") }}'::date,'FUTURE_TRADE_DATE', null),
            iff(coalesce(txn_type, '') not in ('BUY', 'SELL'),  'INVALID_TXN_TYPE', null),
            iff(quantity is null or quantity <= 0,              'INVALID_QUANTITY', null),
            iff(price is null or price <= 0,                    'INVALID_PRICE', null),
            iff(security_id is not null and trade_date is not null and isin_at_trade is null,
                                                                'UNKNOWN_SECURITY', null),
            iff(isin_at_trade is not null and currency is distinct from security_currency,
                                                                'CURRENCY_MISMATCH', null)
        ), ',') as reject_reasons
    from joined
)

-- STEP 4: final status
select
    *,
    -- signed quantity makes position maths trivial downstream
    iff(txn_type = 'BUY', quantity, -quantity) as signed_quantity,
    case when rn > 1 then 'DUPLICATE'
         when reject_reasons <> '' then 'REJECTED'
         else 'ACCEPTED' end as dq_status
from checked

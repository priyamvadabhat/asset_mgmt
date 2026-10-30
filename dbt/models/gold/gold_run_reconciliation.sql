-- =============================================================================
-- GOLD : RUN RECONCILIATION  - one row per dataset for THIS run.
-- records_received is counted straight from RAW, the other columns from SILVER,
-- so  received = accepted + rejected + duplicates  proves nothing was silently lost.
-- =============================================================================
with by_dataset as (
    select 'security_master' as dataset,
           (select count(*) from {{ source('raw', 'security_master') }}) as records_received,
           count_if(dq_status = 'ACCEPTED')  as accepted,
           count_if(dq_status = 'REJECTED')  as rejected,
           count_if(dq_status = 'DUPLICATE') as duplicates
    from {{ ref('silver_security_master') }}

    union all
    select 'transactions',
           (select count(*) from {{ source('raw', 'transactions') }}),
           count_if(dq_status = 'ACCEPTED'), count_if(dq_status = 'REJECTED'), count_if(dq_status = 'DUPLICATE')
    from {{ ref('silver_transactions') }}

    union all
    select 'positions',
           (select count(*) from {{ source('raw', 'positions') }}),
           count_if(dq_status = 'ACCEPTED'), count_if(dq_status = 'REJECTED'), count_if(dq_status = 'DUPLICATE')
    from {{ ref('silver_positions') }}

    union all
    select 'market_prices',
           (select count(*) from {{ source('raw', 'market_prices') }}),
           count_if(dq_status = 'ACCEPTED'), count_if(dq_status = 'REJECTED'), count_if(dq_status = 'DUPLICATE')
    from {{ ref('silver_market_prices') }}

    union all
    select 'restricted_securities',
           (select count(*) from {{ source('raw', 'restricted_securities') }}),
           count_if(dq_status = 'ACCEPTED'), count_if(dq_status = 'REJECTED'), count_if(dq_status = 'DUPLICATE')
    from {{ ref('silver_restricted_securities') }}
)
select
    '{{ invocation_id }}'                         as run_id,
    current_timestamp()                           as run_ts,
    '{{ var("business_date") }}'::date            as business_date,
    dataset,
    records_received,
    accepted,
    rejected,
    duplicates,
    records_received = accepted + rejected + duplicates as is_balanced,
    round(rejected / nullif(records_received, 0), 4)   as reject_rate
from by_dataset

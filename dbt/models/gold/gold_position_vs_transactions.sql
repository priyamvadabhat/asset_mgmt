-- =============================================================================
-- GOLD : POSITION vs TRANSACTION CHECK  (the "no double counting" proof)
-- Compares the reported position quantity with the quantity derived by summing
-- accepted, de-duplicated transactions. If a transaction file were counted twice
-- the derived quantity would be too high and the row would show status BREAK.
--   MATCH            reported = derived
--   BREAK            reported <> derived          (investigate!)
--   NO_TRANSACTIONS  position exists but no accepted trades (e.g. opening balance
--                    or the trade was rejected)
--   NO_POSITION      trades exist but no reported position
-- =============================================================================
with reported as (
    select portfolio_id, security_id, quantity as reported_quantity
    from {{ ref('silver_positions') }}
    where dq_status = 'ACCEPTED'
      and position_date = '{{ var("business_date") }}'::date
),
derived as (
    select portfolio_id, security_id,
           sum(signed_quantity) as derived_quantity,
           count(*)             as accepted_txn_count
    from {{ ref('silver_transactions') }}
    where dq_status = 'ACCEPTED'
      and trade_date <= '{{ var("business_date") }}'::date
    group by 1, 2
)
select
    coalesce(r.portfolio_id, d.portfolio_id) as portfolio_id,
    coalesce(r.security_id,  d.security_id)  as security_id,
    r.reported_quantity,
    d.derived_quantity,
    d.accepted_txn_count,
    case when r.reported_quantity is null then 'NO_POSITION'
         when d.derived_quantity  is null then 'NO_TRANSACTIONS'
         when r.reported_quantity = d.derived_quantity then 'MATCH'
         else 'BREAK' end                    as status,
    '{{ invocation_id }}'                    as run_id
from reported r
full outer join derived d
    on r.portfolio_id = d.portfolio_id and r.security_id = d.security_id

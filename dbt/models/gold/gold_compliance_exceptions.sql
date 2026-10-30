-- =============================================================================
-- GOLD : COMPLIANCE EXCEPTIONS
-- Accepted transactions executed while the security was under an ACTIVE
-- restriction on the trade date (effective-dated join).
--   TRADING_BAN -> any trade is an exception
--   BUY_BAN     -> only BUY trades are exceptions (SELL is allowed)
--   status = LIFTED restrictions are ignored.
-- Each exception is traceable to the transaction row and the restriction row.
-- =============================================================================
select
    md5(t.transaction_id || '|' || r.restriction_type || '|' || r.effective_from::varchar) as exception_id,
    t.transaction_id,
    t.portfolio_id,
    t.security_id,
    t.trade_date,
    t.txn_type,
    t.quantity,
    t.price,
    t.currency,
    r.restriction_type,
    r.effective_from       as restriction_from,
    r.effective_to         as restriction_to,

    -- ---- lineage ----
    t._source_file         as transaction_source_file,
    t._source_row          as transaction_source_row,
    r._source_file         as restriction_source_file,
    r._source_row          as restriction_source_row,
    '{{ invocation_id }}'  as run_id,
    current_timestamp()    as detected_at
from {{ ref('silver_transactions') }} t
join {{ ref('silver_restricted_securities') }} r
    on  r.dq_status = 'ACCEPTED'
    and r.status = 'ACTIVE'
    and r.security_id = t.security_id
    and t.trade_date >= r.effective_from
    and (r.effective_to is null or t.trade_date <= r.effective_to)
    and (r.restriction_type = 'TRADING_BAN'
         or (r.restriction_type = 'BUY_BAN' and t.txn_type = 'BUY'))
where t.dq_status = 'ACCEPTED'
{% if var('inject_failure') %}
  -- FAILURE INJECTION (recovery demo): forces a runtime error in this model, independent of
  -- the other Gold models (they may or may not have finished). See README "Failure injection".
  and to_number('INJECTED_FAILURE') = 1
{% endif %}

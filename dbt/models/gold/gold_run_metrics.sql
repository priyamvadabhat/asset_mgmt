-- =============================================================================
-- GOLD : RUN METRICS - the key business exceptions of this run (name/value rows).
-- Feeds dashboards and alerts (see AUDIT.RUN_METRICS_HISTORY for the trend).
-- =============================================================================
with m as (
    select 'positions_published' as metric_name, count(*) as metric_value
    from {{ ref('gold_portfolio_positions') }}
    union all
    select 'positions_published_with_stale_price_warning', count(*)
    from {{ ref('gold_portfolio_positions') }} where pricing_status = 'STALE_WARN'
    union all
    select 'positions_quarantined_missing_price', count(*)
    from {{ ref('silver_priced_positions') }} where pricing_status = 'MISSING_PRICE'
    union all
    select 'positions_quarantined_stale_price', count(*)
    from {{ ref('silver_priced_positions') }} where pricing_status = 'STALE_PRICE'
    union all
    select 'compliance_exceptions', count(*)
    from {{ ref('gold_compliance_exceptions') }}
    union all
    select 'position_vs_transaction_breaks', count(*)
    from {{ ref('gold_position_vs_transactions') }} where status = 'BREAK'
    union all
    select 'records_in_quarantine', count(*)
    from {{ ref('silver_quarantine') }}
)
select
    '{{ invocation_id }}'              as run_id,
    current_timestamp()                as run_ts,
    '{{ var("business_date") }}'::date as business_date,
    metric_name,
    metric_value
from m

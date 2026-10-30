-- =============================================================================
-- SILVER : QUARANTINE - one place for every record that was NOT trusted.
-- Nothing is deleted: each rejected record keeps its reason codes, file/row
-- lineage and original payload so it can be investigated and re-delivered.
-- DUPLICATE rows are not errors (they are counted in reconciliation instead).
-- =============================================================================

-- ---- Records rejected by validation rules -----------------------------------
select 'security_master' as dataset,
       coalesce(security_id, '<MISSING>') || '|' || coalesce(effective_from::varchar, '<MISSING>') as record_key,
       reject_reasons, _source_file, _source_row, _loaded_at, raw_record
from {{ ref('silver_security_master') }} where dq_status = 'REJECTED'

union all
select 'transactions',
       coalesce(transaction_id, '<MISSING>'),
       reject_reasons, _source_file, _source_row, _loaded_at, raw_record
from {{ ref('silver_transactions') }} where dq_status = 'REJECTED'

union all
select 'positions',
       coalesce(portfolio_id, '<MISSING>') || '|' || coalesce(security_id, '<MISSING>') || '|' || coalesce(position_date::varchar, '<MISSING>'),
       reject_reasons, _source_file, _source_row, _loaded_at, raw_record
from {{ ref('silver_positions') }} where dq_status = 'REJECTED'

union all
select 'market_prices',
       coalesce(security_id, '<MISSING>') || '|' || coalesce(price_date::varchar, '<MISSING>') || '|' || coalesce(price_source, '<MISSING>'),
       reject_reasons, _source_file, _source_row, _loaded_at, raw_record
from {{ ref('silver_market_prices') }} where dq_status = 'REJECTED'

union all
select 'restricted_securities',
       coalesce(security_id, '<MISSING>') || '|' || coalesce(restriction_type, '<MISSING>') || '|' || coalesce(effective_from::varchar, '<MISSING>'),
       reject_reasons, _source_file, _source_row, _loaded_at, raw_record
from {{ ref('silver_restricted_securities') }} where dq_status = 'REJECTED'

-- ---- Valid positions that could not be PRICED (missing / stale price) --------
union all
select 'positions_pricing',
       portfolio_id || '|' || security_id || '|' || position_date::varchar,
       pricing_status, position_source_file, position_source_row, current_timestamp()::timestamp_ntz,
       object_construct('portfolio_id', portfolio_id, 'security_id', security_id,
                        'position_date', position_date, 'quantity', quantity,
                        'latest_price_date', price_date, 'price_age_days', price_age_days)
from {{ ref('silver_priced_positions') }}
where pricing_status in ('MISSING_PRICE', 'STALE_PRICE')

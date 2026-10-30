{{ config(
    post_hook = "alter table {{ this }} modify column isin set masking policy {{ target.database }}.audit.mask_isin"
) }}
-- =============================================================================
-- GOLD : TRUSTED PORTFOLIO POSITIONS with market value + traceability.
-- Only positions that passed validation AND have a usable price are published.
-- (Missing / stale-price positions are in SILVER.SILVER_QUARANTINE instead.)
-- The post_hook re-applies the ISIN masking policy because dbt re-creates the
-- table on every run (analysts see ******1234).
-- =============================================================================
select
    portfolio_id,
    security_id,
    isin,                                   -- ISIN valid ON position_date (effective-dated)
    asset_class,
    position_date,
    quantity,
    currency,
    book_value,
    price,
    price_date,
    price_source,
    price_age_days,
    pricing_status,                         -- CURRENT or STALE_WARN
    quantity * price                        as market_value,        -- local currency (no FX, see design doc)
    quantity * price - book_value           as unrealised_pnl,

    -- ---- traceability / lineage metadata ----
    position_source_file,                   -- which file the position came from
    position_source_row,                    -- ...and which row
    price_source_file,                      -- which file the price came from
    price_source_row,
    '{{ invocation_id }}'                   as run_id,              -- which pipeline run produced this row
    current_timestamp()                     as published_at
from {{ ref('silver_priced_positions') }}
where pricing_status in ('CURRENT', 'STALE_WARN')

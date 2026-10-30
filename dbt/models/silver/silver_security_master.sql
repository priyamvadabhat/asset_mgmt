-- =============================================================================
-- SILVER : security master (effective-dated reference data)
-- Types the raw columns, validates them and flags each row's dq_status.
-- Other models join to this ONLY via  dq_status = 'ACCEPTED'  and an
-- effective-date range, so they always get the version valid on that date
-- (e.g. SEC006 changed ISIN on 2026-10-01).
-- =============================================================================

-- STEP 1: type / clean the raw strings (empty string -> NULL)
with parsed as (
    select
        nullif(trim(security_id), '')            as security_id,
        nullif(trim(isin), '')                   as isin,
        upper(nullif(trim(asset_class), ''))     as asset_class,
        upper(nullif(trim(currency), ''))        as currency,
        try_to_date(nullif(trim(effective_from), '')) as effective_from,
        try_to_date(nullif(trim(effective_to), ''))   as effective_to,
        nullif(trim(effective_to), '')           as effective_to_raw,   -- to tell "blank" from "invalid"
        _source_file, _source_row, _loaded_at,
        object_construct(*)                      as raw_record          -- original record, for quarantine
    from {{ source('raw', 'security_master') }}
),

-- STEP 2: duplicate detection + validation rules
checked as (
    select
        *,
        -- Natural key = security_id + effective_from. Latest delivery wins (corrections).
        row_number() over (
            partition by coalesce(security_id, _source_file || '-' || _source_row::varchar), effective_from
            order by _loaded_at desc, _source_file desc, _source_row desc
        ) as rn,
        -- Each failed rule adds a reason code. Empty string = all rules passed.
        array_to_string(array_construct_compact(
            iff(security_id is null,                                   'MISSING_SECURITY_ID', null),
            iff(isin is null,                                          'MISSING_ISIN', null),
            iff(effective_from is null,                                'INVALID_EFFECTIVE_FROM', null),
            iff(effective_to_raw is not null and effective_to is null, 'INVALID_EFFECTIVE_TO', null),
            iff(effective_to < effective_from,                         'EFFECTIVE_TO_BEFORE_FROM', null),
            iff(currency is null or length(currency) <> 3,             'INVALID_CURRENCY', null)
        ), ',') as reject_reasons
    from parsed
)

-- STEP 3: final status. Duplicate wins over rejected (a superseded row is not an error).
select
    *,
    case when rn > 1 then 'DUPLICATE'
         when reject_reasons <> '' then 'REJECTED'
         else 'ACCEPTED' end as dq_status
from checked

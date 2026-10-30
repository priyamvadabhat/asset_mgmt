-- =============================================================================
-- SILVER : restricted securities (effective-dated restriction list)
-- =============================================================================

-- STEP 1: type / clean
with parsed as (
    select
        nullif(trim(security_id), '')               as security_id,
        upper(nullif(trim(restriction_type), ''))   as restriction_type,
        try_to_date(nullif(trim(effective_from), '')) as effective_from,
        try_to_date(nullif(trim(effective_to), ''))   as effective_to,   -- NULL = open-ended
        nullif(trim(effective_to), '')              as effective_to_raw,
        upper(nullif(trim(status), ''))             as status,
        _source_file, _source_row, _loaded_at,
        object_construct(*)                         as raw_record
    from {{ source('raw', 'restricted_securities') }}
),

-- STEP 2: duplicates + validation
checked as (
    select
        *,
        row_number() over (
            partition by coalesce(security_id, _source_file || '-' || _source_row::varchar), restriction_type, effective_from
            order by _loaded_at desc, _source_file desc, _source_row desc
        ) as rn,
        array_to_string(array_construct_compact(
            iff(security_id is null,                                   'MISSING_SECURITY_ID', null),
            iff(coalesce(restriction_type, '') not in ('TRADING_BAN', 'BUY_BAN'), 'INVALID_RESTRICTION_TYPE', null),
            iff(effective_from is null,                                'INVALID_EFFECTIVE_FROM', null),
            iff(effective_to_raw is not null and effective_to is null, 'INVALID_EFFECTIVE_TO', null),
            iff(effective_to < effective_from,                         'EFFECTIVE_TO_BEFORE_FROM', null),
            iff(coalesce(status, '') not in ('ACTIVE', 'LIFTED'),      'INVALID_STATUS', null)
        ), ',') as reject_reasons
    from parsed
)

select
    *,
    case when rn > 1 then 'DUPLICATE'
         when reject_reasons <> '' then 'REJECTED'
         else 'ACCEPTED' end as dq_status
from checked

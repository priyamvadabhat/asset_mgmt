{# Use the schema name exactly as configured (SILVER / GOLD) instead of dbt's default
   "<target_schema>_<custom_schema>" pattern. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | upper }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}

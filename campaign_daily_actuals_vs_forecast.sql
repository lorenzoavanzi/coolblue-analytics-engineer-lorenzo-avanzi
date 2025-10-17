
/* This model answers the following business question:
   By day and campaign, what were the actual net sales versus the forecast, and what is the variance?
*/

{{ config
    (
        materialized='incremental',
        unique_key=['campaign_sk', 'date'],
        sort='date',
        dist='campaign_sk'
    )
}}

-- I set a lower bound to speed up the initial table creation. Assuming that historical data for campaigns is only
-- available from this year, I set it to 2025-01-01
{% set earliest_date_events = '2025-01-01' %}

-- We use this macro to generate a continuous series of dates between a specified timeframe
{{
   dbt_utils.date_spine(
      datepart="date",
      start_date="'2015-01-01'::DATE",
      end_date="CURRENT_DATE"
      )
}}
   
{% if is_incremental() %}
   WHERE
      (date > (SELECT MAX(t.date) FROM {{ this }} AS t)
   {% endif %}

-- We first look at the actual net sales for each campaign by date
WITH sales_day AS (
    SELECT
        fs.date,
        fs.campaign_sk
        NVL(SUM(fs.net_amount), 0) AS actual_net_sales
    FROM {{ ref('fct_sales') }} AS fs
    WHERE
        fs.campaign_sk IS NOT NULL
        AND (
            {% if is_incremental() %}
                -- Process only rows after the last date_key loaded in this model
                fs.date > (SELECT MAX(t.date) FROM {{ this }} AS t)
            {% else %}
                fs.date_key >= '{{ earliest_date_events }}'
            {% endif %}
        )
    {{ dbt_utils.group_by(2) }}
),

forecast_day AS (
    SELECT
        f.date,
        f.campaign_sk,
        NVL(SUM(f.forecast_amount_day), 0) AS forecast_sales
    FROM {{ ref('fct_campaign_forecast_day') }} AS f
    WHERE
        {% if is_incremental() %}
            -- Mirror the same incremental window as sales_day
            f.date > (SELECT MAX(t.date) FROM {{ this }} AS t)
        {% else %}
            f.date >= '{{ earliest_date_events }}'
        {% endif %}
    {{ dbt_utils.group_by(2) }}
)

SELECT
    ds.date,
    NVL(sd.campaign_sk, fd.campaign_sk) AS campaign_sk,
    dc.campaign_name,
    SUM(sd.actual_net_sales) AS actual_net_sales,
    SUM(fd.forecast_sales) AS forecast_sales,
    actual_net_sales - forecast_sales AS variance_amount
FROM date_sequence AS ds
LEFT JOIN sales_day AS sd
    ON ds.date = sd.date
LEFT JOIN forecast_day AS fd
    ON ds.date = fd.date
INNER JOIN {{ ref('dim_campaign') }} AS dc
    ON dc.campaign_sk = NVL(sd.campaign_sk, fd.campaign_sk)
{{ dbt_utils.group_by(3) }}

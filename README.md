👋 Welcome to my AE Assignment Repo!

Hi future team! Welcome to this repository for my Analytics Engineer assignment about Delta Coffee as part of the Coolblue hiring process.
This project demonstrates how to design and implement a modern analytics stack, from raw data ingestion to a well-modeled warehouse ready for business analysis.

As part of this exercise, I focused on showing how sales and campaign data can be:
- Modeled for flexible, multi-dimensional analysis
- Transformed and prepared using ELT best practices
- Combined to deliver insights into campaign performance, actuals vs. forecasts, and top-performing products and stores

**What does this repo contain?**

- **Schema diagram:** diagrams/schema.mmd (star with fct_sales, fct_campaign_forecast_day, and a bridge to assign sales to campaigns deterministically)
- **Architecture diagram:** diagrams/architecture.mmd (sources → ingestion → staging → core → marts → BI; dbt + tests)
- **dbt-style models:** staging, core dims, bridge, facts, plus example tests
- **Example queries:** in the README for top campaigns and actuals vs forecast.

> ⚠️ In-depth information about approach, assumptions, grains, tests, and how the model
> answers the questions can be found below.

---

# **Section 1: Diagrams**

**1.1. Architecture**

Click [here](diagrams/architecture.pdf) to view.

What does this architecture flow enable?
- Answers sales & quantity by day/week/year, product / product type / store / campaign / manager
- Compares actuals vs. forecast at the same grain (campaign x product × day) for pacing/variance
- Provides the top campaigns by sales and lets stakeholders slice results from many angles

Left → Right
1) Data Sources
- Ordering System: orders, order_lines, products, product_types, stores
- Campaign Management: campaigns, product inclusions (by product or type), managers, forecasts
Why: Different teams own these systems, and they possibly have evolved on their own with slightly different meanings. By modeling them separately from the start, we can track the lineage, keep things auditable, and show where each field originates from

2) Ingestion (Bronze)
How
- Make raw tables one‑to‑one with the source through Fivetran (my choice as it will now integrate with dbt) into a raw (bronze) schema
- Keep the source primary keys, timestamps, soft deletes, and schema evolution fields (like ingested_at, or valid_from, valid_to if we talking about SCD)
- I don't apply any business logic here, just store exact copies

Why
- Bronze acts as the immutable system of record. If downstream rules change (let's say, a new allocation method), we can recompute in a clean way without going back to the source
- It also gives us the ability to replay or reprocess data by time window or by entity (for example, campaign_id)
- The trade off is that storing raw data takes up more space, but the payoff is huge in my opinion: easier debugging, reliable lineage, and the ability to “time travel” when needed

3) Orchestration and Transformation
How
- dbt transforms and runs define lineage and order (staging → dims/bridge → facts)
- Orchestrate with Airflow: morning full run for yesterday; Incremental models (facts) append/merge by date or ID to reduce compute time and costs (for large models mainly)
- We apply tests to model and column level lineage by using dbt's 5 standard data tests, but also leveraging packages like dbt.utils and expectations

Why
- Ensures repeatability, reliability, and early failure detection. We want failures to happen as upstream as possible

Late-arriving & backfills
- If a late order arrives, the bridge lookup by date still assigns the correct campaign (no reprocessing needed)
- If campaign definitions change, we can rebuild the bridge and recompute affected dates/campaigns (bounded backfills)

> For the structure, I went with a star schema style to make things more modular. It helps to keep measures in clear, additive facts and all
>  business context in shared dimensions, so analysts can slice by any angle quickly and consistently.
> The Silver → Gold → Marts split keeps work clean and reliable: Silver standardizes raw data (no business logic), Gold centralizes core rules
>  and conformed entities (SCD dims, campaign bridge), and Marts expose final query-ready models for BI. This structure makes queries
>  fast, definitions consistent, and changes easy to manage without breaking dashboards.

4) Silver (staging layer)
- stg_orders_* and stg_campaigns_* standardize types, column names, and compute only “obvious” fields (e.g., net_amount = amount_total - campaign_discount), and maybe some light deduplications
Why: It shields downstream work from upstream quirks and provides a stable contract for core modeling. This speeds up development since every model starts from clean inputs

5) Gold (Core)

Dimensions (slow changing)
- SCD2: dim_product, dim_product_type, dim_store keep historical attributes so sales roll up as they were at the time of the transaction
- SCD1: dim_campaign, dim_manager capture current identity/labels (usually they do not need historical versions)

Bridge
I introduced the bridge to make campaign attribution deterministic, straightforward, and reliable. Since campaigns can include products either directly (by product) or indirectly (by product type), and can also overlap in time, joining sales straight to the campaign tables would create fanout, ambiguity, and double counting. The bridge solves this by precomputing one row per product × campaign, with valid_from/valid_to windows and a clear precedence rule (product‑level takes priority over type‑level). Facts then join once on date range, ensuring each sale maps to at most one campaign. This centralizes the business logic, keeps reports accurate, supports late‑arriving data and backfills, and makes attribution auditable and easy to adjust in one place.
- bridge_product_campaign expands campaign definitions: unions product-level and product-type-level inclusions,  enforces “one active campaign per product/day” with date windows, tie-breaks in favor of product-level over type-level
Why: a deterministic, auditable mapping from any sale (product, date) to the campaign in force. This keeps the rule centralized and prevents duplicate logic in facts/BI



👋 Welcome to my AE Assignment Repo!

Hi future team! Welcome to this repository for my Analytics Engineer assignment about Delta Coffee as part of the Coolblue hiring process.
This project demonstrates how to design and implement a modern analytics stack, from raw data ingestion to a well-modeled warehouse ready for business analysis.

As part of this exercise, I focused on showing how sales and campaign data can be:
- Modeled for flexible, multi-dimensional analysis
- Transformed and prepared using ELT best practices
- Combined to deliver insights into campaign performance, actuals vs. forecasts, and top-performing products and stores

**What does this repo contain?**

- **Schema diagram:** (within the `diagrams` folder)
- **Architecture diagram:** (within the `diagrams` folder)
- **A dbt-style model that answers a business question:**

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

6) Marts (Facts)
- fct_sales (grain = order_line): Keys to date, product, and store, with optional links to campaign/manager through the bridge. Measures include units, gross, discount, and net sales
- fct_campaign_forecast_day (grain = campaign × product × day): Combines product‑ and type‑level forecasts, allocates type‑level forecasts down to products, and spreads them across days within the campaign window
Why: Both fact tables line up on date + product + campaign. That makes actual vs. forecast a straightforward join, giving you clean variance and pacing metrics across any dimension

7) BI / Analyses
- Semantic metrics (Net Sales, Units, Discount, Forecast, Variance) exposed to Looker/Tableau
- Stakeholders can slice by time, product/type, store, campaign, manager and rank top campaigns

**1.1. Schema**

Click [here](diagrams/schema.pdf) to view.

Instead of starting by looking at the tables, I began with the business questions: sales & quantity by time/product/store/campaign/manager, actuals vs. forecast, and top campaigns. After all, the most important questions when starting a schema structure is what does the final output look like and why do they want this. In short:** "What business question should this answer?"**
I mapped those to the metrics we need (units, gross, discount, net, forecast, variance/pacing), then identified the minimal set of models to support them. To keep things clear and maintainable, I used a layered approach: Silver → Gold → Marts, so raw inputs are standardized, core rules (history, attribution) are defined once, and the final star schema is clean for BI or analyses.

**Schema at a glance (what & why):**
Facts
- FCT_SALES (order-line grain): additive measures (units, gross, discount, net), keys to date/product/store and (if applicable) campaign/manager
- FCT_CAMPAIGN_FORECAST_DAILY (campaign×product×day): forecast distributed to the same grain as actuals: simple actual vs. forecast joins and pacing

Dimensions
- Conformed dims: DIM_DATE, DIM_PRODUCT, DIM_PRODUCT_TYPE, DIM_STORE, DIM_CAMPAIGN, DIM_MANAGER
- SCD2 on Product/Product Type/Store (historically correct rollups). SCD1 on Campaign/Manager (non changing identity/labels)

Bridge
- BRIDGE_PRODUCT_CAMPAIGN expands type-level campaign definitions to products, applies product over type precedence, and enforces one active campaign per product/day. This way it is deterministic, auditable attribution with a single date range join

**Why this schema vs. other options (trade-offs)**

I went with a star schema because it gives us clear grains, additive measures, and fast many-to-one joins. Conformed dimensions make slicing in BI tools simple and consistent: perfect for campaign and sales analytics. Other options had trade-offs that did not fit this use case:
- Snowflake adds more normalization, but the extra joins and complexity don’t bring much value here
- One-big-table might seem convenient at first, but it leads to duplication, fuzzy metrics, messy history, and a high risk of double counting, specially with overlapping campaigns
- Data Vault is great for tracking ingestion and lineage at scale, but it is not so BI-friendly without a star layer on top, and it would add more complexity than we need
- Querying sources directly skips modeling, but it is slow and hard to manage for SCDs or history, and spreads business logic across reports

The star schema, paired with a layered warehouse has the right balance: fast queries, clean logic, and good governance. All without overcomplicating things.

**Data tests I would include:**

Firstly, I would leverage the 5 dbt standard data tests on model and column-level lineage, but also go for external packages like dbt.utils and expectations for more complex testing.

Integrity
- Uniqueness/Not null: order_line_id, order_id, campaign_id. Foreign keys in facts (product/store/date/campaign where applicable)
- Relationships: Every product_id/store_id/campaign_id in facts exists in its dim

Business rules
- No overlapping windows in BRIDGE_PRODUCT_CAMPAIGN for the same product_id (one active campaign per product/day)
- Precedence test: if a product is both in product-level and type-level for the same campaign dates, ensure product-level wins

SCD correctness
- Exactly one current row per business key in SCD2 dims; non-overlapping effective_from/to windows

Freshness & completeness
- Source freshness checks (orders and campaigns updated as expected)
- Volume/variance checks (e.g., order_lines per day, negative amounts, abnormal spikes/drops vs 7/28-day baselines)

Monitoring and alerting (business critical metrics):
- Automation: run dbt tests in dbt Cloud (or CI) on PR + at night. Also, block deploys on failures
- Elementary for dbt to watch freshness, nulls, distribution drift
- Metric anomalies with Slack alerts

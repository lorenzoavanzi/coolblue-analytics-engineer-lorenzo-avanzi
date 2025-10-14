👋 Welcome to my AE Assignment Repo!

**Coolblue Analytics Engineer Assignment: Delta Coffee**

Hi future team! Welcome to this repository for my Analytics Engineer assignment as part of the Coolblue hiring process.
This project demonstrates how to design and implement a modern analytics stack, from raw data ingestion to a well-modeled warehouse ready for business analysis.

The goal of this exercise is to show how sales and campaign data can be:
- Modeled for flexible, multi-dimensional analysis
- Transformed and prepared using ELT best practices
- Combined to deliver insights into campaign performance, actuals vs. forecasts, and top-performing products and stores

---

**What does this repo contain?**

- **Schema diagram (Mermaid):** diagrams/schema.mmd (star with fct_sales, fct_campaign_forecast_day, and a bridge to assign sales to campaigns deterministically)
- **Architecture diagram (Mermaid):** diagrams/architecture.mmd (sources → ingestion → staging → core → marts → BI; dbt + tests)
- **dbt-style models:** staging, core dims, bridge, facts, plus example tests
- **Example queries:** in the README for top campaigns and actuals vs forecast.

> ⚠️ In-depth information about approach, assumptions, grains, tests, and how the model
> answers the questions can be found below.


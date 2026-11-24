
# SaaS Product Growth, Retention & Churn Analytics

An end-to-end **product analytics** project for a B2B project-management SaaS. It follows customers from signup to
paid conversion, retention, churn and lifetime value using **Python, MySQL, Power BI and Excel**.

> Most portfolio dashboards show sales. This one shows behaviour: how users move through a funnel, who stays,
> who leaves, and what each acquisition channel is actually worth.

---

## Business problem

The company is growing, but leadership cannot answer four questions:

1. Is MRR growth healthy, or is new revenue being eaten by churn?
2. Which acquisition channels bring customers who **pay and stay**, not just sign up?
3. Are newer customer cohorts retaining better or worse than older ones?
4. How much is a customer worth compared with what it costs to acquire them?

## Dashboard pages (Power BI)

| # | Page | Question it answers |
|---|------|---------------------|
| 01 | **Growth Overview** | Is MRR growing, and where does the growth come from? |
| 02 | **Acquisition & Conversion** | Where do users drop off, and which channels convert best? |
| 03 | **Cohort Retention Analysis** | Do customers stay, and are newer cohorts better or worse? |
| 04 | **Churn, CAC & Customer Value** | Who churns, why, and is each channel profitable (LTV:CAC)? |

<!-- Add screenshots after you build the dashboard:
![Growth Overview](outputs/figures/01_growth_overview.png)
![Acquisition & Conversion](outputs/figures/02_acquisition_conversion.png)
![Cohort Retention](outputs/figures/03_cohort_retention.png)
![Churn, CAC & Customer Value](outputs/figures/04_churn_cac_value.png)
-->

## Key results

| Metric | Result |
|--------|--------|
| Monthly recurring revenue (Sep 2026) | **$44,125** (ARR about $530K) |
| Paying customers | **508** |
| Signup to paid conversion | **15.4%** |
| Average monthly logo churn (last 6 months) | **4.6%** |
| Monthly churn: monthly plans vs annual plans | **6.9% vs 1.4%** |
| Share of churn caused by failed payments | **23%** (recoverable) |
| Best paid channel by LTV:CAC | **Partner, 5.0x** |
| Worst paid channel by LTV:CAC | **Facebook Ads, 0.63x** |

Full findings and recommendations: [documentation/key_insights.md](documentation/key_insights.md)

## What this project demonstrates

- **Data cleaning and validation:** messy multi-table data, 17 logged data-quality checks
- **Product analytics:** funnel, activation, cohort retention, survival analysis
- **Subscription finance metrics:** MRR bridge, NRR, GRR, ARPA, CAC, LTV, LTV:CAC, payback period
- **SQL:** funnel, MRR, cohorts, churn, retention and LTV queries
- **Modelling:** RFM and K-Means segmentation, churn prediction with a time-based split, MRR forecast
- **Experimentation:** A/B test design with sample size, SRM check and confidence intervals
- **BI and validation:** four-page Power BI dashboard and Excel KPI reconciliation

## Tools

| Tool | Used for |
|------|----------|
| Python (pandas, numpy, scikit-learn, matplotlib, seaborn) | Cleaning, validation, cohorts, churn, survival, segmentation, churn model, forecast |
| MySQL | Funnel, MRR, cohort, churn, retention and LTV queries |
| Power BI | Four-page interactive dashboard |
| Excel | Independent KPI validation |

## Dataset

Five tables: **users, events, subscriptions, payments, marketing spend** (Jan 2024 to Sep 2026).
The data is synthetic and deliberately messy: duplicates, mixed date formats, inconsistent categories,
test accounts and money stored as text. See [documentation/data_dictionary.md](documentation/data_dictionary.md).

## Repository structure

```
saas-analytics/
├── README.md
├── data/
│   ├── raw/                 # original messy CSV files
│   └── processed/           # cleaned tables
├── mysql_import/            # CSV files prepared for MySQL
├── notebooks/
│   └── data_cleaning_and_eda.ipynb
├── sql/                     # MySQL queries
├── powerbi/                 # .pbix dashboard file
├── excel/
│   └── kpi_validation.xlsx
├── outputs/
│   ├── figures/             # charts
│   └── reports/
└── documentation/
    ├── business_questions.md
    ├── data_dictionary.md
    ├── methodology.md
    └── key_insights.md
```

## Workflow

1. **Clean and validate** the raw data in Python and log every data-quality issue.
2. **Load** the clean tables into MySQL.
3. **Build metrics in SQL:** funnel, MRR bridge, cohorts, churn, retention, LTV.
4. **Analyse in Python:** cohort retention, survival curves, segmentation, churn model.
5. **Visualise in Power BI** (four pages).
6. **Validate in Excel:** reconcile KPIs across Python, SQL, Power BI and Excel.

## How to reproduce

1. Clone the repository and place the raw CSV files in `data/raw/`.
2. Install the requirements: `pip install pandas numpy matplotlib seaborn scipy scikit-learn sqlalchemy pymysql`
3. Run `notebooks/data_cleaning_and_eda.ipynb` from top to bottom (**Run All**).
4. Create the MySQL database and tables, then load the cleaned data (see `sql/`).
5. Run the queries in `sql/`.
6. Open `powerbi/` and refresh the data source.

## Documentation

| File | Contents |
|------|----------|
| [business_questions.md](documentation/business_questions.md) | The questions each dashboard page answers |
| [data_dictionary.md](documentation/data_dictionary.md) | Every table and column, with cleaning applied |
| [methodology.md](documentation/methodology.md) | Cleaning, validation, metric definitions, methods, assumptions |
| [key_insights.md](documentation/key_insights.md) | Findings and recommendations |

## Limitations

The data is synthetic, so behavioural signals are weaker than in real product data. CAC is calculated at channel
level without attribution. Observational data shows correlation only, so the proposed A/B tests are needed
for causal claims. See [methodology.md](documentation/methodology.md) for details.

## Author

Solayma molla  | [LinkedIn](https://www.linkedin.com/in/solaymamolla ) | [GitHub](https://github.com/shifamolla24) | [shifamolla24@gmail.com]

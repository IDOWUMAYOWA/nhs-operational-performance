# NHS Operational Performance Analytics Platform

**Microsoft Fabric \| PySpark \| Delta Lake \| Power BI \| Terraform \|
Azure DevOps**

## Purpose

The **NHS Operational Performance Analytics Platform** is an end-to-end
cloud data engineering and business intelligence solution built to
analyse NHS hospital operational performance using publicly available,
aggregate NHS data.

The platform integrates emergency-care activity, elective waiting-list
performance, and NHS organisation reference data into a governed
analytical model that answers the core business question:

> **How are NHS hospital services performing over time, and where are
> there signs of operational pressure?**

The solution demonstrates a production-style Microsoft data engineering
workflow covering ingestion, distributed transformation, data quality,
API integration, dimensional modelling, orchestration, infrastructure as
code, CI/CD, operational monitoring, and Power BI analytics.

No patient-level or confidential health information is used.

------------------------------------------------------------------------

## Architecture

``` text
                     NHS England Public Data
                              │
             ┌────────────────┼────────────────┐
             │                │                │
        A&E Monthly      RTT Monthly        ODS API
          Files            Files          Reference Data
             │                │                │
             └────────────────┼────────────────┘
                              ▼
                  Microsoft Fabric Data Factory
                              │
                              ▼
                    Bronze Lakehouse Layer
                  Raw files + API snapshots
                              │
                              ▼
                    PySpark / Delta Lake
                              │
                              ▼
                    Silver Lakehouse Layer
             Cleaned, validated, conformed data
                              │
                              ▼
                     Gold Analytics Layer
              Dimensions + Facts + KPI tables
                              │
                              ▼
                   Power BI Semantic Model
                              │
                              ▼
                 Operational Performance Dashboard

       Terraform ─────► Infrastructure / Configuration
       Azure DevOps ──► Git, CI/CD and Environment Promotion
```

The data platform follows a **Bronze → Silver → Gold medallion
architecture**, separating raw ingestion, reusable conformed data, and
business-ready analytical models.

------------------------------------------------------------------------

## Data Sources

### A&E Attendances and Emergency Admissions

Monthly NHS England provider-level A&E data is used to analyse emergency
activity and four-hour performance.

**Coverage**

``` text
September 2025 → August 2026
```

**Processed records**

``` text
2,341 provider-month records
12 reporting months
```

The pipeline removes national and aggregate `TOTAL` records to preserve
provider-level analytical grain.

### Referral to Treatment (RTT)

NHS England **Incomplete Provider** workbooks provide elective
waiting-list measures by NHS provider and treatment function.

**Coverage**

``` text
August 2025 → July 2026
```

**Processed records**

``` text
42,936 records
12 reporting months
24 treatment functions
```

RTT analytical grain:

``` text
reporting_month
+ provider_code
+ treatment_function_code
```

### NHS Organisation Data Service

The NHS Organisation Data Service is used to enrich provider codes with
authoritative organisation metadata.

The solution builds a provider universe from A&E and RTT and retrieves
missing organisations through the ODS API. API responses are persisted
as dated Bronze snapshots so downstream processing remains reproducible
and is not dependent on a live API.

The final reference dataset contains:

``` text
218 providers
218 distinct provider codes
```

Provider participation across the performance datasets:

``` text
68  A&E only
136 A&E + RTT
14  RTT only
```

------------------------------------------------------------------------

## Data Flow

### Bronze Layer --- Raw Data Ingestion

Microsoft Fabric Data Factory ingests source data into the Lakehouse
while preserving source fidelity.

Historical A&E and RTT files are loaded using metadata-driven `ForEach`
activities rather than maintaining individual copy activities for every
reporting month.

``` text
Files/
└── bronze/
    ├── ae/
    │   ├── 2025-09/
    │   ├── 2025-10/
    │   └── ...
    ├── rtt/
    │   ├── 2025-08/
    │   ├── 2025-09/
    │   └── ...
    └── ods_api/
        └── snapshot_date=YYYY-MM-DD/
            └── provider_snapshot.json
```

This structure supports historical replay, source traceability, and
month-level processing.

### Silver Layer --- Transformation and Data Quality

`NB_02_Silver_Transformations` converts heterogeneous source files into
standardised Delta tables.

Transformations include:

-   standardising source columns to `snake_case`;
-   normalising NHS provider codes and names;
-   parsing reporting periods into consistent date fields;
-   removing aggregate A&E `TOTAL` records;
-   converting RTT placeholder values such as `-` to `NULL`;
-   casting analytical measures to appropriate numeric types;
-   validating reporting months and mandatory business fields;
-   checking duplicate business keys;
-   assigning data-quality statuses;
-   building the historical provider universe;
-   enriching missing organisations through the ODS API;
-   validating ODS coverage;
-   snapshotting organisation reference data;
-   performing idempotent Delta `MERGE` operations.

Silver outputs:

``` text
silver_ae_performance
silver_rtt_waiting_list
silver_provider_reference
```

### Gold Layer --- Analytics Model

`NB_03_Gold_Data_Model` transforms Silver data into a dimensional model
optimised for reporting and Power BI.

Gold outputs:

``` text
dim_provider
dim_date
dim_specialty
fact_ae_performance
fact_rtt_waiting_list
gold_provider_monthly_kpi
```

Small dimensions are rebuilt from their conformed Silver sources, while
larger facts and KPI tables use Delta `MERGE` to support repeatable and
incremental processing.

------------------------------------------------------------------------

## Data Model

The Gold layer follows a dimensional/star-schema design.

``` text
                     dim_provider
                    /      |      \
                   /       |       \
                  ▼        ▼        ▼
       fact_ae_performance │ gold_provider_monthly_kpi
                           │
                           ▼
                fact_rtt_waiting_list
                    ▲            ▲
                    │            │
               dim_date    dim_specialty
```

### `dim_provider`

Contains the conformed NHS provider reference.

``` text
218 rows
218 unique provider codes
```

### `dim_date`

Provides reporting-month attributes across the combined analytical
period.

``` text
August 2025 → August 2026
13 reporting months
```

### `dim_specialty`

Contains RTT treatment-function reference values.

``` text
24 treatment functions
```

### `fact_ae_performance`

Provider-month A&E performance fact.

Business key:

``` text
reporting_month + provider_code
```

Current historical size:

``` text
2,341 rows
```

### `fact_rtt_waiting_list`

Provider-month-treatment-function RTT fact.

Business key:

``` text
reporting_month
+ provider_code
+ treatment_function_code
```

Current historical size:

``` text
42,936 rows
```

### `gold_provider_monthly_kpi`

Provider-month analytical KPI table combining available A&E and RTT
measures.

Business key:

``` text
reporting_month + provider_code
```

Current size:

``` text
2,645 rows
```

The combined model spans 13 months because A&E and RTT publication
periods do not align exactly.

------------------------------------------------------------------------

## Data Quality Framework

Data quality is enforced throughout Silver and Gold rather than being
treated as a separate reporting exercise.

Validation includes:

-   mandatory provider-code checks;
-   provider-name validation;
-   valid reporting-month checks;
-   duplicate business-key detection;
-   treatment-function validation;
-   numeric type validation;
-   placeholder-to-`NULL` conversion;
-   provider-reference coverage checks;
-   ODS API response validation;
-   fact-grain validation;
-   source-to-target row-count checks;
-   A&E business-rule checks.

A&E validation ensures:

``` text
total attendances >= 0
attendances over four hours <= total attendances
four-hour performance is between 0% and 100%
```

The historical source contains 146 records where four-hour performance
is `NULL`. Investigation showed that these correspond to provider-month
records with zero total A&E attendances.

These values are deliberately retained as `NULL` because a percentage
with a zero denominator is undefined; converting them to zero would
introduce a false performance value.

------------------------------------------------------------------------

## Idempotent and Incremental Processing

The platform supports safe reruns and incremental ingestion through
business-key-based Delta Lake `MERGE` operations.

### A&E

``` text
reporting_month
+ provider_code
```

### RTT

``` text
reporting_month
+ provider_code
+ treatment_function_code
```

### Provider KPI

``` text
reporting_month
+ provider_code
```

Matching records are updated and new records are inserted without
duplicating existing business keys.

Incremental processing identifies new or revised reporting periods and
processes only the affected data before merging the results into the
existing Silver and Gold Delta tables.

Historical records outside the incoming processing scope are preserved.

The solution intentionally avoids global
`whenNotMatchedBySourceDelete()` behaviour because an incremental batch
may contain only a subset of reporting periods. Deleting target records
absent from that subset could incorrectly remove valid historical data.

------------------------------------------------------------------------

## ODS Snapshot Strategy

ODS organisation reference data is managed as a slowly changing external
reference source.

The enrichment workflow is:

``` text
Build provider universe
        │
        ▼
Read latest previous ODS snapshot
        │
        ▼
Identify missing provider codes
        │
        ▼
Retrieve missing organisations from ODS API
        │
        ▼
Validate API responses
        │
        ▼
Combine existing + new organisations
        │
        ▼
Write dated Bronze snapshot
        │
        ▼
Re-read and validate snapshot
        │
        ▼
Build silver_provider_reference
```

The design avoids unnecessary API requests when all provider codes
already exist in the previous snapshot.

Snapshotting also protects analytical reproducibility if organisation
metadata changes in the external service.

------------------------------------------------------------------------

## Pipeline Orchestration

The Fabric orchestration pipeline is:

``` text
PL_NHS_Operational_Performance
```

Core execution flow:

``` text
ForEach_RTT_Files ──────┐
                        │
                        ├──► Run_NB_02_Silver
                        │           │
ForEach_AE_Files ───────┘           ▼
                              Run_NB_03_Gold
                                     │
                                     ▼
                           Analytics-ready Gold
```

Both Bronze ingestion branches must complete successfully before Silver
processing begins.

Silver and Gold execute sequentially to enforce transformation
dependencies.

Pipeline parameters support environment-specific and load-specific
execution:

``` text
environment
load_type
run_id
```

The Fabric pipeline RunId is propagated into transformation and logging
activities for traceability.

------------------------------------------------------------------------

## Failure Handling and Operational Logging

Pipeline execution metadata is captured in:

``` text
pipeline_run_log
```

The operational log contains:

``` text
run_id
environment
load_type
pipeline_name
stage
status
started_at
completed_at
error_message
```

A dedicated failure-logging component captures orchestration failures
across ingestion and transformation stages.

``` text
NB_04_Pipeline_Failure_Log
```

Failure dependencies are configured so unsuccessful activities route to
the operational logging path with the relevant stage and error
information.

The design separates:

``` text
SUCCESS execution logging
from
FAILURE orchestration logging
```

This provides a central audit trail for pipeline monitoring and
troubleshooting.

Spark notebook activities use a shared high-concurrency session strategy
where appropriate, reducing unnecessary Spark-session startup and
improving pipeline resource utilisation.

------------------------------------------------------------------------

## Power BI Semantic Model

The Gold Lakehouse layer is exposed to Power BI through a dimensional
semantic model.

Relationships use **one-to-many, single-direction filtering from
dimensions to facts**.

``` text
dim_provider  1 ─── * fact_ae_performance
dim_provider  1 ─── * fact_rtt_waiting_list
dim_provider  1 ─── * gold_provider_monthly_kpi

dim_date      1 ─── * fact_ae_performance
dim_date      1 ─── * fact_rtt_waiting_list
dim_date      1 ─── * gold_provider_monthly_kpi

dim_specialty 1 ─── * fact_rtt_waiting_list
```

Direct fact-to-fact relationships are avoided.

This keeps filtering predictable and prevents ambiguous relationship
paths.

------------------------------------------------------------------------

## Power BI Dashboard

The Power BI report provides an executive view of NHS operational
performance across emergency and elective services.

### Executive Overview

The landing page summarises:

-   A&E four-hour performance;
-   total A&E attendances;
-   attendances exceeding four hours;
-   RTT waiting-list size;
-   provider coverage;
-   reporting-period coverage;
-   month-over-month movement.

### A&E Performance

The A&E report page analyses:

-   four-hour performance over time;
-   total emergency attendances;
-   attendances exceeding four hours;
-   provider-level performance;
-   provider trends by reporting month;
-   variation across NHS organisations.

### RTT Waiting Lists

The RTT page analyses:

-   waiting-list size over time;
-   provider-level waiting-list trends;
-   treatment-function performance;
-   median waiting time;
-   92nd-percentile waiting time;
-   specialties with the largest elective backlogs.

### Provider Performance

The provider page combines available A&E and RTT indicators at
provider-month level.

Users can filter by:

``` text
Provider
Reporting Month
Treatment Function
Organisation Status
Organisation Type
```

This allows analysts to identify providers showing sustained or
increasing operational pressure across the available measures.

### Analytical Interpretation

The dashboard is designed to identify:

-   changes in operational performance over time;
-   providers with consistently weaker A&E performance;
-   providers with large or growing elective waiting lists;
-   specialties contributing heavily to elective backlog;
-   periods where emergency and elective pressure occur simultaneously.

The model does **not** infer causation between A&E demand and RTT
waiting-list performance. The datasets are aggregate observational
measures, so the report presents trends and associations rather than
causal conclusions.

------------------------------------------------------------------------

## Power BI Measures

The semantic model includes reusable measures for operational reporting,
including:

``` text
Total A&E Attendances
Attendances Over 4 Hours
A&E 4-Hour Performance %
RTT Waiting List
Median RTT Waiting Time
92nd Percentile RTT Waiting Time
Provider Count
Month-over-Month Change
```

Measures are defined in the semantic layer rather than embedded
independently in individual visuals, keeping business logic reusable and
consistent across report pages.

------------------------------------------------------------------------

## Infrastructure as Code

Terraform is used to manage supported infrastructure and configuration
as code.

Infrastructure code is separated from analytical transformation logic so
environment configuration can be version controlled and reproduced
consistently.

Example repository structure:

``` text
infrastructure/
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── environments/
        ├── dev/
        ├── test/
        └── prod/
```

Terraform is used where supported by the Microsoft Fabric/Azure control
plane.

Fabric SaaS artefacts that are better managed through Fabric-native Git
integration or deployment pipelines remain under the appropriate Fabric
lifecycle mechanism rather than being artificially forced into
Terraform.

This creates a practical separation between:

``` text
Infrastructure / configuration → Terraform

Fabric analytical artefacts     → Git + deployment lifecycle
```

------------------------------------------------------------------------

## Azure DevOps and CI/CD

Azure DevOps provides source control and automated delivery for the
platform.

The development workflow follows:

``` text
Developer Change
      │
      ▼
Feature Branch
      │
      ▼
Pull Request
      │
      ▼
Validation
      │
      ▼
Main Branch
      │
      ▼
Deployment Pipeline
      │
      ├──► Development
      ├──► Test
      └──► Production
```

Version-controlled assets include:

-   Fabric notebooks;
-   pipeline definitions;
-   infrastructure code;
-   environment configuration;
-   semantic-model artefacts;
-   Power BI project assets;
-   documentation.

CI/CD validation checks project structure and deployable artefacts
before environment promotion.

Environment-specific values are parameterised rather than hard-coded
into transformation notebooks.

------------------------------------------------------------------------

## Environment Strategy

The project separates development, test and production configuration.

``` text
DEV
 │
 ▼
TEST
 │
 ▼
PROD
```

Environment parameters control deployment-specific configuration while
transformation logic remains consistent.

This supports repeatable releases and reduces the risk of manually
changing production assets.

------------------------------------------------------------------------

## Technologies Used

  Technology            Purpose
  --------------------- ---------------------------------------------
  Microsoft Fabric      Unified data and analytics platform
  Fabric Data Factory   Metadata-driven ingestion and orchestration
  Fabric Lakehouse      Bronze, Silver and Gold storage
  Apache Spark          Distributed data processing
  PySpark               Transformation and data-quality logic
  Delta Lake            ACID storage and idempotent `MERGE`
  Python                API integration and processing utilities
  pandas                Excel source ingestion
  NHS ODS API           Provider reference enrichment
  Power BI              Semantic modelling and dashboards
  DAX                   Reusable analytical measures
  Terraform             Infrastructure/configuration as code
  Azure DevOps          Git, CI/CD and environment promotion

------------------------------------------------------------------------

## Historical Model Validation

The completed historical Gold model contains:

  Table                             Rows
  ----------------------------- --------
  `dim_provider`                     218
  `dim_date`                          13
  `dim_specialty`                     24
  `fact_ae_performance`            2,341
  `fact_rtt_waiting_list`         42,936
  `gold_provider_monthly_kpi`      2,645

Validation confirms:

``` text
218 distinct provider codes
24 distinct treatment functions
13 combined reporting months
0 duplicate Gold business keys
```

------------------------------------------------------------------------

## Repository Structure

``` text
nhs-operational-performance/
│
├── README.md
│
├── notebooks/
│   ├── NB_01_Bronze_Data_Profiling
│   ├── NB_02_Silver_Transformations
│   ├── NB_03_Gold_Data_Model
│   └── NB_04_Pipeline_Failure_Log
│
├── pipelines/
│   └── PL_NHS_Operational_Performance
│
├── power-bi/
│   ├── semantic-model/
│   ├── report/
│   └── screenshots/
│
├── infrastructure/
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── environments/
│
├── azure-devops/
│   └── pipelines/
│
└── docs/
    ├── architecture/
    ├── data-model/
    └── pipeline/
```

------------------------------------------------------------------------

## Key Engineering Decisions

### Medallion Architecture

The solution separates data responsibilities into three layers:

``` text
Bronze → source fidelity and replayability
Silver → cleaning, validation and conformance
Gold   → business-ready analytical models
```

This improves traceability and makes ingestion, transformation, and
reporting issues easier to isolate.

### Metadata-Driven Ingestion

Monthly source files are processed using parameterised `ForEach`
activities rather than duplicated pipeline components.

This reduces maintenance as new reporting periods become available.

### Delta Lake MERGE

Business-key-based `MERGE` operations make repeated pipeline execution
idempotent and support revised NHS source data without generating
duplicates.

### ODS Snapshotting

External reference data is snapshotted before transformation so
analytical results remain reproducible even when upstream organisation
metadata changes.

### Separate Reporting Periods

A&E and RTT are published on different schedules.

The model preserves the actual reporting month of each source rather
than forcing asynchronous datasets into an artificial common period.

### Dimensional Gold Model

The reporting layer uses dimensions and facts instead of exposing raw
Silver tables directly to Power BI.

This provides clearer analytical grain, reusable relationships, and
simpler business measures.

### Centralised Operational Logging

Pipeline RunIds, stages, execution status, timestamps, and error
information are captured centrally to improve observability and
troubleshooting.

### Infrastructure and Deployment Separation

Terraform manages supported infrastructure/configuration, while
Fabric-native lifecycle mechanisms and Azure DevOps manage analytical
artefacts.

This avoids treating every SaaS object as traditional infrastructure.

------------------------------------------------------------------------

## Engineering Challenges Solved

### Incomplete Provider Reference Coverage

The original organisation reference extract covered only part of the
provider universe.

The solution dynamically identified missing providers, queried the ODS
API, validated responses, and expanded the reference layer to all **218
required provider codes**.

### Historical Aggregate Records

A historical A&E file contained a `TOTAL` row whose period field looked
like a normal reporting month.

Filtering only on the period field was therefore insufficient.

The Silver logic was strengthened to exclude aggregate records using
period, organisation code, and organisation name.

### Stale Records After MERGE

Delta `MERGE` correctly updated and inserted records but did not
automatically remove a previously loaded aggregate record that had later
become invalid under improved transformation rules.

The stale aggregate record was explicitly removed without enabling
global source-missing deletion, preserving safety for future incremental
batches.

### Heterogeneous RTT Excel Workbooks

RTT data is published as Excel workbooks with non-tabular leading rows
and placeholder values.

The ingestion process dynamically handles the Provider worksheet header
structure, removes empty columns, standardises schemas, and converts
analytical placeholders before Spark processing.

### External API Schema Consistency

Direct Spark inference of nested Python API responses produced
incompatible nested types when combined with existing snapshots.

Serialising new responses to JSON and reading them through Spark
produced a consistent nested schema suitable for snapshot union and
downstream flattening.

### Spark Capacity and Session Management

Pipeline testing exposed Spark session-allocation constraints.

Notebook execution was configured to reuse high-concurrency sessions
where appropriate, reducing unnecessary session creation while
preserving pipeline sequencing.

------------------------------------------------------------------------

## Business Value

The platform converts fragmented NHS operational publications into a
single analytics-ready model.

It enables analysts and operational stakeholders to:

-   monitor emergency-care performance over time;
-   track elective waiting-list pressure;
-   compare NHS providers consistently;
-   investigate treatment-function backlogs;
-   identify sustained operational pressure;
-   distinguish genuine trends from individual monthly observations;
-   access governed KPIs through a reusable semantic model.

The architecture also reduces manual monthly preparation by automating
ingestion, validation, transformation, enrichment, modelling, and
dashboard refresh.

------------------------------------------------------------------------

## Skills Demonstrated

This project demonstrates practical experience across the modern
Microsoft data engineering stack:

``` text
Data integration
Data pipeline orchestration
Microsoft Fabric
PySpark
Distributed data processing
Delta Lake
Lakehouse architecture
Data quality engineering
REST API integration
Historical snapshotting
Incremental processing
Dimensional modelling
Power BI
DAX
Infrastructure as Code
Terraform
Git
Azure DevOps
CI/CD
Environment promotion
Operational monitoring
Failure handling
Business-facing analytics
```

------------------------------------------------------------------------

## Summary

The NHS Operational Performance Analytics Platform provides an
end-to-end implementation of a modern cloud analytics architecture using
Microsoft Fabric.

The solution integrates **12 months of A&E data**, **12 months of RTT
data**, and a validated **218-provider organisation reference**,
producing a **13-month analytical model** containing more than **45,000
detailed operational records**.

Raw public NHS data is ingested through metadata-driven Fabric
pipelines, transformed using PySpark, persisted in Delta Lake, validated
through business and technical data-quality controls, modelled into
dimensional Gold tables, and exposed through a Power BI semantic model
and operational dashboard.

Terraform provides infrastructure/configuration as code, while Azure
DevOps provides version control, CI/CD, and controlled environment
promotion.

The result is a reproducible, observable, idempotent and analytics-ready
data platform designed around real-world NHS operational reporting
requirements.

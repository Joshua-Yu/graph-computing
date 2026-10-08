<#
.SYNOPSIS
    Creates the Network Search repository folder structure.

.DESCRIPTION
    Mirrors docs/deployment/repo-structure.txt. Safe to re-run: existing
    folders and files are never overwritten.

    Git does not track empty folders, so a .gitkeep file is placed in every
    folder that would otherwise be empty.

.PARAMETER Root
    Folder to create the structure in. Defaults to the current folder, so run
    it from the root of your cloned repo.

.PARAMETER MaxDepth
    How many folder levels to create. Defaults to 2 (for example
    src/ingestion, but not infrastructure/terraform/environments). Use 0 to
    create the full structure. Deeper folders are meant to be added as
    content arrives.

.PARAMETER WithFiles
    Also create the files named in the structure (README.md, the docs/*.md
    pages, workflow YAMLs, cypher scripts) as empty placeholders. Files whose
    folder is deeper than MaxDepth are skipped.

.EXAMPLE
    cd C:\repos\network-search
    powershell -ExecutionPolicy Bypass -File .\create-repo-structure.ps1

.EXAMPLE
    .\create-repo-structure.ps1 -Root C:\repos\network-search -MaxDepth 0 -WithFiles
#>
[CmdletBinding()]
param(
    [string]$Root = (Get-Location).Path,
    [int]$MaxDepth = 2,
    [switch]$WithFiles
)

$ErrorActionPreference = 'Stop'

$folders = @'
.github

.github/workflows
.github/ISSUE_TEMPLATE

docs

docs/01-overview

docs/02-architecture
docs/02-architecture/diagrams

docs/03-graph-fundamentals

docs/04-modeling-guidelines

docs/05-data

docs/06-ingestion

docs/07-risk-and-fraud

docs/08-hume

docs/09-operations
docs/09-operations/runbooks

docs/10-security-governance

docs/11-testing

docs/12-decisions

docs/13-deployment

model

model/graph-schema
model/graph-schema/diagrams
model/domain
model/domain/party
model/domain/account
model/domain/service
model/domain/transaction
model/domain/device
model/domain/address
model/domain/organisation
model/domain/risk
model/mappings
model/mappings/warehouse
model/mappings/kafka
model/mappings/external-sources

data-contracts

data-contracts/warehouse
data-contracts/warehouse/customer
data-contracts/warehouse/account
data-contracts/warehouse/service
data-contracts/warehouse/transaction
data-contracts/kafka
data-contracts/kafka/customer-events
data-contracts/kafka/account-events
data-contracts/kafka/transaction-events
data-contracts/kafka/service-events
data-contracts/external-sources
data-contracts/schemas

src

src/ingestion
src/ingestion/day0
src/ingestion/kafka
src/ingestion/transformation
src/ingestion/validation
src/ingestion/entity-resolution
src/ingestion/dead-letter
src/graph
src/graph/loaders
src/graph/queries
src/graph/algorithms
src/graph/utilities
src/risk
src/risk/features
src/risk/rules
src/risk/scoring
src/risk/explanations
src/investigation
src/investigation/search
src/investigation/case-management
src/common

cypher

cypher/schema
cypher/migrations
cypher/ingestion
cypher/queries
cypher/fraud-patterns
cypher/risk-features
cypher/investigation
cypher/administration
cypher/diagnostics

orchestration

orchestration/hume
orchestration/hume/orchestra
orchestration/hume/workflows
orchestration/hume/configurations
orchestration/pipelines

infrastructure

infrastructure/terraform
infrastructure/terraform/modules
infrastructure/terraform/environments
infrastructure/terraform/environments/dev
infrastructure/terraform/environments/test
infrastructure/terraform/environments/staging
infrastructure/terraform/environments/prod
infrastructure/helm
infrastructure/kubernetes
infrastructure/docker
infrastructure/kafka-connect

config

config/dev
config/test
config/staging
config/prod

tests

tests/unit
tests/integration
tests/graph
tests/contract
tests/data-quality
tests/reconciliation
tests/performance
tests/security

test-data

test-data/synthetic
test-data/graph-fixtures
test-data/kafka-events
test-data/expected-results

notebooks

notebooks/exploration
notebooks/graph-analysis
notebooks/fraud-pattern-analysis
notebooks/performance

scripts

scripts/bootstrap
scripts/local-dev
scripts/migration
scripts/deployment
scripts/data-validation
scripts/utilities

monitoring

monitoring/dashboards
monitoring/alerts
monitoring/metrics
monitoring/log-config

examples

examples/cypher
examples/python
examples/kafka
examples/graph-model
examples/investigations

tools

tools/schema-validation
tools/data-generation
'@ -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$files = @'
README.md
CONTRIBUTING.md
CODEOWNERS
CHANGELOG.md
.gitignore
.editorconfig
.pre-commit-config.yaml

.github/workflows/ci.yml
.github/workflows/security-scan.yml
.github/workflows/terraform-plan.yml
.github/workflows/release.yml
.github/pull_request_template.md

docs/01-overview/solution-overview.md
docs/01-overview/business-context.md
docs/01-overview/scope.md
docs/01-overview/use-cases.md
docs/01-overview/glossary.md

docs/02-architecture/solution-architecture.md
docs/02-architecture/data-flow.md
docs/02-architecture/integration-architecture.md
docs/02-architecture/security-architecture.md

docs/03-graph-fundamentals/neo4j-basics.md
docs/03-graph-fundamentals/cypher-guidelines.md
docs/03-graph-fundamentals/graph-patterns.md

docs/04-modeling-guidelines/modeling-principles.md

docs/05-data/source-inventory.md
docs/05-data/source-definitions.md
docs/05-data/canonical-definitions.md
docs/05-data/entity-resolution.md
docs/05-data/data-lineage.md
docs/05-data/data-quality.md
docs/05-data/retention.md

docs/06-ingestion/day0-load.md
docs/06-ingestion/incremental-load.md
docs/06-ingestion/kafka-ingestion.md
docs/06-ingestion/replay-strategy.md
docs/06-ingestion/reconciliation.md
docs/06-ingestion/idempotency.md
docs/06-ingestion/failure-handling.md

docs/07-risk-and-fraud/risk-scoring.md
docs/07-risk-and-fraud/fraud-patterns.md
docs/07-risk-and-fraud/network-search-patterns.md
docs/07-risk-and-fraud/feature-engineering.md
docs/07-risk-and-fraud/explainability.md
docs/07-risk-and-fraud/investigation-use-cases.md

docs/08-hume/orchestra-design.md
docs/08-hume/investigation-workflow.md
docs/08-hume/integration.md
docs/08-hume/workflow-patterns.md

docs/09-operations/monitoring.md
docs/09-operations/alerting.md
docs/09-operations/backup-restore.md
docs/09-operations/disaster-recovery.md
docs/09-operations/capacity-management.md
docs/09-operations/performance-tuning.md

docs/10-security-governance/access-control.md
docs/10-security-governance/pii-handling.md
docs/10-security-governance/encryption.md
docs/10-security-governance/audit.md
docs/10-security-governance/data-classification.md
docs/10-security-governance/segregation-of-duties.md
docs/10-security-governance/regulatory-considerations.md

docs/11-testing/test-strategy.md
docs/11-testing/data-testing.md
docs/11-testing/graph-testing.md
docs/11-testing/integration-testing.md
docs/11-testing/performance-testing.md
docs/11-testing/reconciliation-testing.md

docs/12-decisions/adr/ADR-001-use-neo4j.md
docs/12-decisions/adr/ADR-002-graph-model.md
docs/12-decisions/adr/ADR-003-event-ingestion.md

docs/13-deployment/repo-structure.txt

cypher/schema/bootstrap.cypher
cypher/migrations/V001__initial_schema.cypher
cypher/migrations/V002__add_transaction_indexes.cypher

test-data/README.md

notebooks/README.md
'@ -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if ($MaxDepth -gt 0) {
    $folders = $folders | Where-Object { ($_ -split '/').Count -le $MaxDepth }
    $files = $files | Where-Object { ($_ -split '/').Count - 1 -le $MaxDepth }
}

if (-not (Test-Path -LiteralPath $Root)) {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}
$Root = (Resolve-Path -LiteralPath $Root).Path

$created = @{ Folders = 0; Files = 0; Gitkeep = 0 }

foreach ($folder in $folders) {
    $path = Join-Path $Root $folder
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $created.Folders++
    }
}

if ($WithFiles) {
    foreach ($file in $files) {
        $path = Join-Path $Root $file
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType File -Path $path -Force | Out-Null
            $created.Files++
        }
    }
}

# Git ignores empty folders - drop a .gitkeep into each one so it can be committed.
foreach ($folder in $folders) {
    $path = Join-Path $Root $folder
    if (-not (Get-ChildItem -LiteralPath $path -Force | Select-Object -First 1)) {
        New-Item -ItemType File -Path (Join-Path $path '.gitkeep') | Out-Null
        $created.Gitkeep++
    }
}

Write-Host "Network Search structure ready in $Root"
Write-Host ("  folders created : {0}" -f $created.Folders)
Write-Host ("  files created   : {0}" -f $created.Files)
Write-Host ("  .gitkeep added  : {0}" -f $created.Gitkeep)

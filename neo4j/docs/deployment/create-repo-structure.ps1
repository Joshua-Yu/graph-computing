<#
.SYNOPSIS
    Creates the Network Search repository folder structure.

.DESCRIPTION
    Mirrors docs/13-deployment/repo-structure.txt. Safe to re-run: existing
    folders and files are never overwritten.

    Git does not track empty folders, so a .gitkeep file is placed in every
    folder that would otherwise be empty.

.PARAMETER Root
    Folder to create the structure in. Defaults to the current folder, so run
    it from the root of your cloned repo.

.PARAMETER MaxDepth
    How many folder levels to create. Defaults to 2 (for example
    spec/contracts, but not spec/contracts/crm). Use 0 to
    create the full structure. Deeper folders are meant to be added as
    content arrives.

.PARAMETER WithFiles
    Also create the files named in the structure (README.md, the docs/*.md
    pages, workflow YAMLs, spec schemas and templates) as empty placeholders. Files whose
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

spec
spec/model
spec/model/domain
spec/model/domain/party
spec/model/domain/account
spec/model/domain/service
spec/model/domain/transaction
spec/model/domain/device
spec/model/domain/address
spec/model/domain/organisation
spec/model/domain/risk
spec/model/diagrams
spec/contracts
spec/contracts/crm
spec/contracts/crm/customer
spec/contracts/core-banking
spec/contracts/core-banking/account
spec/contracts/core-banking/transaction
spec/contracts/external-sources
spec/products
spec/products/risk-scores
spec/products/alerts
spec/products/cases
spec/schemas
spec/transforms
spec/meta
spec/templates

generated
generated/cypher
generated/cypher/migrations
generated/cypher/loaders
generated/cypher/reconciliation
generated/python
generated/jobs
generated/jobs/day0
generated/jobs/cdc
generated/kafka-connect
generated/rbac
generated/dq-checks
generated/monitoring
generated/monitoring/alerts
generated/monitoring/dashboards
generated/docs
generated/docs/data-dictionary
generated/docs/lineage
generated/test-data

src
src/ingestion
src/ingestion/day0
src/ingestion/kafka
src/ingestion/transformation
src/ingestion/validation
src/ingestion/entity-resolution
src/ingestion/dead-letter
src/graph
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

orchestration
orchestration/hume
orchestration/pipelines

infrastructure
infrastructure/terraform
infrastructure/terraform/modules
infrastructure/terraform/environments
infrastructure/terraform/environments/dev
infrastructure/terraform/environments/sit
infrastructure/terraform/environments/nft
infrastructure/terraform/environments/prod
infrastructure/helm
infrastructure/kubernetes
infrastructure/docker
infrastructure/kafka-connect

config
config/dev
config/sit
config/nft
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

tools
tools/contractctl
tools/contractctl/commands
tools/contractctl/generators
tools/contractctl/templates
tools/contractctl/rules
tools/contractctl/tests
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
.github/workflows/contract-ci.yml
.github/workflows/release.yml
.github/workflows/deploy.yml
.github/workflows/security-scan.yml
.github/workflows/terraform-plan.yml
.github/pull_request_template.md

docs/01-overview/solution-overview.md
docs/02-architecture/solution-architecture.md
docs/02-architecture/integration-architecture.md
docs/02-architecture/security-architecture.md
docs/03-graph-fundamentals/graph-database-basics.md
docs/03-graph-fundamentals/graph-algorithms.md
docs/04-modeling-guidelines/modeling-principles.md
docs/05-data/data-contract-guideline.md
docs/05-data/canonical-model.md
docs/05-data/source-contract.md
docs/05-data/mapping-guide.md
docs/05-data/product-contract.md
docs/05-data/contract-versioning.md
docs/06-ingestion/day0-load.md
docs/06-ingestion/incremental-load.md
docs/06-ingestion/kafka-ingestion.md
docs/06-ingestion/replay-strategy.md
docs/06-ingestion/reconciliation.md
docs/06-ingestion/idempotency.md
docs/06-ingestion/failure-handling.md
docs/07-risk-and-fraud/risk-scoring.md
docs/08-hume/orchestra-design.md
docs/08-hume/investigation-workflow.md
docs/08-hume/integration.md
docs/08-hume/workflow-patterns.md
docs/09-operations/monitoring.md
docs/09-operations/backup-restore.md
docs/09-operations/disaster-recovery.md
docs/09-operations/capacity-management.md
docs/09-operations/performance-tuning.md
docs/10-security-governance/access-control.md
docs/10-security-governance/data-classification.md
docs/11-testing/test-strategy.md
docs/11-testing/data-testing.md
docs/11-testing/graph-testing.md
docs/11-testing/integration-testing.md
docs/11-testing/performance-testing.md
docs/11-testing/reconciliation-testing.md
docs/13-deployment/repo-structure.txt
docs/13-deployment/contract-pipeline.md

spec/model/access.yaml
spec/transforms/transforms.yaml
spec/meta/model.schema.json
spec/meta/contract.schema.json
spec/meta/product.schema.json
spec/templates/dataset.contract.xlsx
spec/templates/product.yaml

generated/README.md

test-data/README.md

tools/contractctl/README.md
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

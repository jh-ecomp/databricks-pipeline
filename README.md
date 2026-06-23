# SwiftLogix Data Platform

Pipeline de dados para a SwiftLogix — operadora de frota de 5.000 veículos e 10 centros de
triagem em 2 países, processando ~20 milhões de eventos/dia.

## Visão Geral da Arquitetura

```
┌──────────────────────────────────────────────────────┐
│              LANDING ZONE (fora do Lakehouse)        │
│                                                      │
│  S3 (JSON)                  DB Réplica (RDS/Aurora)  │
│  • Retenção por compliance  • Retenção por compliance│
│  • Intelligent Tiering      • Sem papel analítico    │
│  • NÃO é Bronze             • NÃO é Bronze           │
└──────────────┬──────────────────────┬────────────────┘
               │  Databricks lê daqui │
               ▼                      ▼
┌─────────────────────────────────────────────────────┐
│         BRONZE — System of Record do Lakehouse      │
│                                                     │
│  • Formato: Parquet (Delta Lake)                    │
│  • Particionamento adequado                         │
│  • Schema evolution controlada                      │
│  • raw_payload preservado                           │
│  • Retenção longa (system of record real)           │
│  • Mínima transformação de negócio                  │
└─────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────┐
│  SILVER — Curated & Enriched (swiftlogix_silver)     │
│  • Deduplicação (MERGE INTO com chave de negócio)    │
│  • Parsing e normalização de campos                  │
│  • Enriquecimento (join com dados de referência)     │
│  • Validação de qualidade (Great Expectations)       │
└──────────────────────────────────┬───────────────────┘
                                   │
                                   ▼
┌───────────────────────────────────────────────────────────────────────┐
│  GOLD — Serving Layer (swiftlogix_gold)                               │
│  ├─ ops_dashboard      → Dashboard operacional (SLA D-1, query < 10s) │
│  ├─ financial_recon    → Relatório financeiro semanal (D-1)           │
│  └─ eta_features       → Feature store para modelos de ML             │
└───────────────────────────────────────────────────────────────────────┘
```

## Stack Tecnológico

| Componente | Tecnologia |
|------------|-----------|
| Processamento | Databricks (Structured Streaming + Delta Lake) |
| Armazenamento | Delta Lake |
| Catálogo | Unity Catalog |
| Segredos | AWS Secrets Manager |
| Qualidade de Dados | Great Expectations |
| IaC | Terraform |
| CI/CD | GitHub Actions |
| Testes | pytest-bdd |

## Estrutura do Repositório

```
swiftlogix-data-platform/
├── PROJECT_STATUS.md          # Estado atual do projeto (ler primeiro em cada sessão)
├── README.md
├── docs/
│   └── adr/                   # Architecture Decision Records
├── notebooks/
│   ├── bronze/                # Notebooks de ingestão
│   ├── silver/                # Notebooks de curadoria
│   ├── gold/                  # Notebooks de serving
│   ├── reconciliation/        # Batch noturno de reconciliação
│   └── utils/                 # Funções compartilhadas
├── tests/
│   ├── bdd/features/          # Arquivos .feature (Gherkin)
│   ├── unit/                  # Testes unitários das funções
│   ├── integration/           # Testes de integração do pipeline
│   └── quality/               # Great Expectations suites
├── config/
│   └── contracts/             # Representação local dos Data Contracts
├── infrastructure/
│   ├── terraform/             # IaC para recursos AWS + Databricks
│   └── scripts/               # Scripts de bootstrap e deploy
└── .github/
    └── workflows/             # CI/CD pipelines
```

## Como Contribuir

1. Toda nova feature começa com o arquivo `.feature` (BDD) em `tests/bdd/features/`
2. Em seguida, implementar os testes em `tests/unit/` ou `tests/integration/`
3. Só então implementar o notebook/código
4. Qualquer decisão arquitetural relevante deve gerar um novo ADR em `docs/adr/`

## ADRs

| # | Título | Status |
|---|--------|--------|
| [ADR-001](docs/adr/ADR-001-medallion-architecture.md) | Arquitetura Medallion e Stack de Processamento | Proposto |
| [ADR-002](docs/adr/ADR-002-schema-contracts-drift-detection.md) | Contratos de Dados e Detecção de Schema Drift | Proposto |
| [ADR-003](docs/adr/ADR-003-unity-catalog.md) | Catálogo de Dados — Unity Catalog | Proposto (aguardando confirmação) |

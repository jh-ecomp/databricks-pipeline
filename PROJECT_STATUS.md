# SwiftLogix Data Platform — Project Status

> **INSTRUÇÃO PARA O ASSISTENTE:** Este é o PRIMEIRO arquivo a ser lido em qualquer sessão.
> Leia também o `docs/adr/` para decisões já tomadas antes de propor qualquer mudança arquitetural.

---

## Status Geral

| Item | Status |
|------|--------|
| Estrutura do repositório | ✅ Criada |
| ADR-001: Arquitetura Medallion | ✅ Aprovado |
| ADR-002: Schema drift e contratos | ✅ Aprovado |
| ADR-003: Unity Catalog | ✅ Aprovado |
| ADR-004: Landing Zone vs Bronze + política de transformação | ✅ Aprovado |
| BDD features — Bronze (telemetria veículos) | ✅ Criado |
| BDD features — Bronze (centros de triagem) | ✅ Criado |
| BDD features — Bronze (transacional / DB réplica) | ✅ Criado |
| Contratos de dados YAML (vehicle_telemetry, sorting_scans, shipments, manifests) | ⏳ Próximo passo |
| Implementação Bronze — step definitions (pytest-bdd) | ⏳ Próximo passo |
| Implementação Bronze — notebooks | ⬜ Não iniciada |
| BDD features — Silver | ⬜ Não iniciada |
| Implementação Silver | ⬜ Não iniciada |
| BDD features — Gold | ⬜ Não iniciada |
| Implementação Gold | ⬜ Não iniciada |

---

## Decisões Abertas

Nenhuma decisão arquitetural pendente no momento.

---

## Arquitetura Alvo (rascunho — sujeito a confirmação)

```
Fontes                  Bronze (Raw)           Silver (Curated)        Gold (Serving)
──────                  ────────────           ────────────────        ──────────────
S3 JSON (telemetria) ──► bronze.vehicle_events ──► silver.shipment_     ──► gold.ops_dashboard
                                                    events_enriched         gold.financial_recon
DB Réplica (transac.) ──► bronze.shipments     ──►                     ──► gold.eta_features
                          bronze.manifests
```

**Stack:**
- Processamento: Databricks (Structured Streaming + Delta Lake)
- Catálogo: Unity Catalog (decisão pendente)
- Segredos: AWS Secrets Manager
- IaC: Terraform
- CI/CD: GitHub Actions
- Qualidade de dados: Great Expectations (integrado ao pipeline)
- Testes BDD: pytest-bdd

---

## Log de Sessões

| Sessão | Data | O que foi feito |
|--------|------|-----------------|
| 01 | 2025-04 | Estrutura do repositório criada, ADRs 001-003 rascunhados, decisões abertas levantadas |
| 02 | 2025-04 | ADR-004 aprovado (Landing Zone vs Bronze, flatten na Bronze, política de transformação). BDD features da Bronze criados para as 3 fontes: telemetria S3, scans de triagem S3, transacional DB réplica |

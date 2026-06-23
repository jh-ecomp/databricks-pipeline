# ADR-003: Catálogo de Dados — Unity Catalog

**Status:** Proposto (aguardando confirmação)  
**Data:** 2025-04  
**Decisores:** Equipe SwiftLogix Data Platform  

---

## Contexto

A stack é Databricks sobre AWS. Precisamos de um catálogo para:
- Governança de acesso a dados (column-level security para dados financeiros)
- Lineage automático entre tabelas (Bronze → Silver → Gold)
- Registro de contratos de dados e políticas de qualidade
- Descoberta de dados para a equipe de DS

As opções principais são **AWS Glue Catalog** (como Hive Metastore externo) e **Unity Catalog**
(metastore nativo do Databricks).

---

## Decisão

**Unity Catalog** como catálogo e metastore principal.

### Estrutura de namespaces

```
catalog.schema.table

swiftlogix_bronze.events.vehicle_telemetry
swiftlogix_bronze.events.sorting_center_scans
swiftlogix_bronze.events.schema_violations
swiftlogix_bronze.transactional.shipments
swiftlogix_bronze.transactional.manifests

swiftlogix_silver.logistics.shipment_events_enriched
swiftlogix_silver.logistics.cold_chain_readings

swiftlogix_gold.serving.ops_dashboard
swiftlogix_gold.serving.financial_reconciliation
swiftlogix_gold.serving.eta_features

swiftlogix_observability.monitoring.pipeline_runs
swiftlogix_observability.monitoring.data_quality_results
swiftlogix_observability.monitoring.pipeline_alerts
```

### Por que Unity Catalog sobre Glue

| Feature | Unity Catalog | Glue Metastore |
|---------|--------------|----------------|
| Lineage automático | ✅ Nativo | ❌ Não disponível |
| Column-level security | ✅ | ❌ Requer Lake Formation separado |
| Data sharing (Delta Sharing) | ✅ | ❌ |
| Integração com Databricks Jobs | ✅ Nativa | ⚠️ Configuração adicional |
| Audit log centralizado | ✅ | ⚠️ Parcial via CloudTrail |

---

## Consequências

**Positivas:**
- Lineage automático = investigação de incidentes mais rápida (tipo do incidente anterior)
- Governança de acesso centralizada (dados financeiros sensíveis)
- Audit log de quem acessou o quê e quando

**Negativas / Trade-offs:**
- Lock-in no Databricks (mitigado pelo fato de já estar no Databricks)
- Custo adicional do Unity Catalog (cobrado por consulta no catálogo em alguns tiers)

---

## Nota sobre AWS Glue

O Glue pode ser utilizado como **destino de dados** (ex: tabelas consumidas por outros serviços AWS
como Athena ou Redshift Spectrum), mas não como metastore principal do Databricks.

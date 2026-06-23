# ADR-001: Arquitetura Medallion e Stack de Processamento

**Status:** Proposto  
**Data:** 2025-04  
**Decisores:** Equipe SwiftLogix Data Platform  

---

## Contexto

A SwiftLogix processa ~20 milhões de eventos/dia com pico de 1.500 eventos/segundo. O pipeline
atual é um único batch job noturno que gera defasagem de até 24h. Um incidente de schema drift
silencioso causou 11 dias de dados corrompidos e prejuízo de US$ 480 mil.

Os requisitos da nova plataforma são:
- Dashboards operacionais com latência máxima D-1
- Relatório financeiro semanal em D-1
- Feature store para modelos de ETA da equipe de DS
- Histórico de 90 dias com queries < 10 segundos
- Alta observabilidade e detecção proativa de schema drift

---

## Decisão

Adotar arquitetura **Medallion (Bronze → Silver → Gold)** sobre **Delta Lake**, operando no
**Databricks** sobre **AWS**.

### Camadas

| Camada | Propósito | Formato | Retenção |
|--------|-----------|---------|----------|
| **Bronze** | Ingestão raw, sem transformação de negócio | Delta (schema-on-read com schema hints) | 1 ano |
| **Silver** | Dados limpos, validados, enriquecidos, deduplicados | Delta | 1 ano |
| **Gold** | Agregações e modelos de leitura para consumidores | Delta | 90 dias (hot) + 1 ano (cold) |

### Modelo de Processamento

**Micro-batch com `trigger(availableNow=True)`** para os pipelines Bronze → Silver e Silver → Gold:
- Executa a cada 15 minutos via job schedule no Databricks
- Processa exatamente o que chegou desde a última execução (watermark por `ingestion_timestamp`)
- Comporta-se como batch: idempotente, re-executável, sem estado de streaming de longa duração
- Garante SLA D-1 com folga para o dashboard operacional

**Batch noturno de reconciliação** (mantido):
- Executa às 2h da manhã
- Reprocessa as últimas 24h para corrigir late arrivals e garantir consistência financeira

### Por que não Streaming Contínuo?

- Os consumidores downstream (dashboards, relatórios, DS) têm SLA D-1, não real-time
- Streaming contínuo adicionaria complexidade operacional (checkpoints, estado, reprocessamento)
  sem benefício claro dado os SLAs existentes
- `availableNow` oferece semântica exactly-once de forma mais simples

---

## Consequências

**Positivas:**
- Reprocessamento simples: basta reexecutar o job com o range de datas desejado
- Isolamento de falha por camada
- Schema evolution controlada pelo Delta Lake

**Negativas / Trade-offs:**
- Latência mínima de ~15 minutos (aceitável dado SLA D-1)
- Dois jobs para manter (micro-batch + reconciliação noturna)

---

## Alternativas Consideradas

| Alternativa | Descartada porque |
|-------------|-------------------|
| Manter batch diário | Não atende SLA D-1 com margem de segurança |
| Streaming contínuo Kafka→Spark | Complexidade operacional desproporcional aos SLAs |
| DLT (Delta Live Tables) | Reduz controle sobre idempotência e reprocessamento; adequado para próxima iteração |

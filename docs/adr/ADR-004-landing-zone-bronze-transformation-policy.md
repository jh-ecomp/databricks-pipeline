# ADR-004: Landing Zone, Camada Bronze e Política de Transformação

**Status:** Aprovado  
**Data:** 2026-04  
**Decisores:** Equipe SwiftLogix Data Platform  

---

## Contexto

A arquitetura inicial assumia que o S3 (eventos JSON) e o banco de dados réplica eram a camada
Bronze. Esse entendimento foi corrigido: essas fontes são uma **Landing Zone transiente**, com
retenção ditada exclusivamente por compliance/regulação, sem papel analítico no Lakehouse.

---

## Decisão

### 1. Landing Zone — definição e responsabilidades

| Fonte | Tecnologia | Responsabilidade |
|-------|-----------|------------------|
| Eventos de telemetria | S3 (JSON, Intelligent Tiering) | Entrega dos dados brutos; retenção regulatória |
| Dados transacionais | RDS/Aurora (read replica) | Fonte transacional; sem papel analítico |

A Landing Zone **não faz parte do Lakehouse**. O Databricks a consome mas não a gerencia.
Nenhuma query analítica aponta para a Landing Zone.

### 2. Bronze — System of Record do Lakehouse

A Bronze é a **única fonte de verdade histórica** dos dados raw dentro do Lakehouse.
Uma vez ingeridos na Bronze, os dados podem ser reprocessados para Silver/Gold sem retornar
à Landing Zone.

**Responsabilidades da Bronze:**
- Conversão de formato (JSON → Parquet/Delta)
- Particionamento por `event_date` e `source_type`
- Schema evolution controlada (ver ADR-002)
- Flatten completo do JSON aninhado (ver decisão abaixo)
- Preservação do `raw_payload` (JSON original como string)
- Zero lógica de negócio

### 3. Flatten na Bronze — decisão e justificativa

O JSON aninhado será **completamente achatado na Bronze**, não na Silver.

**Exemplo:**
```
# Payload original (Landing Zone)
{
  "delivery_window": { "start": "08:00", "end": "12:00" },
  "vehicle": { "id": "V-1042", "temp_celsius": -4.2 }
}

# Bronze (após flatten)
delivery_window__start   STRING
delivery_window__end     STRING
vehicle__id              STRING
vehicle__temp_celsius    DOUBLE
```

Convenção de nomenclatura para campos achatados: separador duplo underscore (`__`) para
distinguir visualmente campos originalmente aninhados de campos flat nativos.

**Justificativa:** Achatar na Bronze expõe breaking changes de schema (renomeações, campos
removidos) no momento mais cedo possível — no micro-batch de ingestão — em vez de deixá-los
latentes até a Silver. Isso endereça diretamente o incidente `delivery_window.start →
delivery.window_start` que causou 11 dias de dados corrompidos.

O `raw_payload` é preservado como coluna adicional para permitir re-flatten caso a lógica
de parsing precise ser corrigida retroativamente.

### 4. Transformações permitidas e proibidas na Bronze

| Operação | Permitida na Bronze? |
|----------|---------------------|
| Conversão JSON → Delta/Parquet | ✅ |
| Particionamento | ✅ |
| Flatten de JSON aninhado | ✅ |
| Schema evolution (adição de campos) | ✅ (com flag de drift) |
| Adição de colunas de metadados (`ingestion_timestamp`, `pipeline_run_id`, `source`) | ✅ |
| Casting de tipos básicos (string → timestamp, string → double) | ✅ |
| Deduplicação | ❌ (Silver) |
| Enriquecimento / joins | ❌ (Silver) |
| Regras de negócio | ❌ (Silver/Gold) |
| Agregações | ❌ (Gold) |

---

## Consequências

**Positivas:**
- Schema drift detectado no primeiro micro-batch após a mudança
- Bronze é auto-suficiente para reprocessamento histórico completo
- Separação clara de responsabilidades entre Landing Zone e Lakehouse

**Negativas / Trade-offs:**
- Flatten na Bronze significa que mudanças de schema upstream quebram o contrato mais cedo
  (isso é intencional — fail fast)
- O `raw_payload` aumenta o volume de armazenamento da Bronze em ~30-40%
  (aceitável dado o custo de S3/Delta vs o custo de um incidente como o anterior)

# ADR-002: Contratos de Dados e Detecção de Schema Drift

**Status:** Proposto  
**Data:** 2025-04  
**Decisores:** Equipe SwiftLogix Data Platform  

---

## Contexto

O incidente crítico que motivou a replatformação foi um schema drift silencioso: o campo
`delivery_window.start` foi renomeado para `delivery.window_start` por uma API parceira sem
notificação, causando 11 dias de dados corrompidos e US$ 480 mil de prejuízo.

A nova plataforma deve detectar qualquer desvio de schema **antes** que dados corrompidos
cheguem à camada Silver.

---

## Decisão

### 1. Contratos de Dados como artefatos versionados no repositório

Cada fonte de dados terá um **Data Contract** em formato YAML no diretório `config/contracts/`.
O contrato define:
- Schema esperado (campos, tipos, nulabilidade)
- Regras de qualidade (ranges, cardinalidades, formatos)
- Metadados de ownership (produtor, consumidor, SLA, criticidade)
- Versão do contrato e política de breaking changes

Embora o arquivo físico exista no repositório (contexto fictício), o código de produção
**sempre lê o contrato a partir do Unity Catalog** (Schema Registry / Table Properties),
garantindo governança centralizada.

### 2. Validação de Schema na entrada da Bronze

Na chegada de cada micro-batch:
1. Inferir schema do payload recebido
2. Comparar contra o contrato registrado
3. **Campos novos (adições):** logar warning, aceitar com flag `schema_drift_detected=True`
4. **Campos removidos ou renomeados (breaking):** rejeitar o batch, acionar alerta imediato,
   escrever registros na tabela `bronze.schema_violations` com payload original preservado
5. **Mudança de tipo:** tratar como breaking change

### 3. Quarentena em vez de descarte

Registros que violam o contrato **nunca são descartados**. Eles são escritos em:
```
bronze.<source>_quarantine
```
com colunas adicionais:
- `violation_type`: MISSING_FIELD | TYPE_MISMATCH | UNKNOWN_FIELD | BREAKING_RENAME
- `violation_detail`: descrição legível
- `raw_payload`: o JSON original intacto
- `ingestion_timestamp`, `pipeline_run_id`

Isso permite reprocessamento quando o contrato é atualizado.

### 4. Alertas

Qualquer breaking change aciona:
- Alerta no canal de dados (Slack/PagerDuty via webhook em AWS Secrets Manager)
- Registro em `observability.pipeline_alerts` com severidade `CRITICAL`

---

## Consequências

**Positivas:**
- O incidente `delivery_window.start` teria sido detectado no primeiro micro-batch (15 minutos),
  não 11 dias depois
- Dados originais sempre preservados para reprocessamento
- Contratos versionados via Git = histórico de mudanças auditável

**Negativas / Trade-offs:**
- Overhead de validação de schema em cada micro-batch (~ms por batch, aceitável)
- Requer disciplina de atualização dos contratos quando mudanças são intencionais

---

## Alternativas Consideradas

| Alternativa | Descartada porque |
|-------------|-------------------|
| `mergeSchema=True` sem validação | Mascara breaking changes silenciosamente (exatamente o problema atual) |
| Validação apenas na Silver | Dados corrompidos já estariam na Bronze sem marcação |
| Schema Registry Confluent | Faz sentido com Kafka; não temos Kafka neste stack |

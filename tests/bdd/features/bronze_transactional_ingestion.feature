# language: en

Feature: Bronze ingestion — transactional data from database replica
  As a data platform
  I want to ingest shipment and manifest records from the RDS read replica into the Bronze layer
  So that transactional data is available as the system of record without relying on CDC

  Background:
    Given the Unity Catalog catalog "swiftlogix_bronze" exists
    And the schema "transactional" exists within "swiftlogix_bronze"
    And the Delta table "swiftlogix_bronze.transactional.shipments" exists and is partitioned by "updated_date"
    And the Delta table "swiftlogix_bronze.transactional.manifests" exists and is partitioned by "updated_date"
    And the data contracts for "shipments" and "manifests" are registered in Unity Catalog
    And AWS Secrets Manager contains valid JDBC credentials for the RDS read replica

  # ---------------------------------------------------------------------------
  # Watermark-based incremental extraction (no CDC available)
  # ---------------------------------------------------------------------------

  Scenario: Extract new and updated shipment records since last successful run
    Given the last successful ingestion run has a recorded high-watermark timestamp
    And new or updated shipment records exist in the replica with "updated_at" after the watermark
    When the Bronze transactional ingestion job runs
    Then only records with "updated_at" strictly greater than the last watermark are extracted
    And all extracted records are written to "swiftlogix_bronze.transactional.shipments"
    And each record contains "ingestion_timestamp", "pipeline_run_id", and "source"
    And "source" is set to "rds_replica_transactional"
    And the new high-watermark is persisted as the maximum "updated_at" of the extracted batch
    And the job run is recorded in "swiftlogix_observability.monitoring.pipeline_runs" with status "SUCCESS"

  Scenario: No records updated since last watermark results in a no-op run
    Given no records in the replica have "updated_at" after the last recorded watermark
    When the Bronze transactional ingestion job runs
    Then no records are written to "swiftlogix_bronze.transactional.shipments"
    And the watermark value is not changed
    And the job completes with status "SUCCESS" and "records_ingested" recorded as 0

  Scenario: Watermark is persisted atomically with the data write
    Given a batch of updated shipment records is ready for ingestion
    When the Bronze transactional ingestion job writes the batch to Delta
    Then the watermark update and the data write are committed in the same atomic operation
    And if the job fails after writing data but before persisting the watermark, the next run re-extracts and re-writes the same batch without net duplication

  # ---------------------------------------------------------------------------
  # Idempotency
  # ---------------------------------------------------------------------------

  Scenario: Re-running the job with the same watermark window does not duplicate records
    Given a batch of shipment records was successfully ingested in the last run
    And the watermark was correctly persisted after that run
    When the job is run again without any new records in the replica
    Then the record count in "swiftlogix_bronze.transactional.shipments" does not increase

  Scenario: Forced full re-extraction for a historical date range produces correct state
    Given an operator triggers a full re-extraction for a specific date range
    When the Bronze transactional ingestion job runs in backfill mode for that range
    Then existing records in the target partitions are overwritten, not appended
    And the final record count matches the source replica record count for that date range

  # ---------------------------------------------------------------------------
  # Schema drift
  # ---------------------------------------------------------------------------

  Scenario: New nullable column added to the replica table (non-breaking)
    Given the data contract defines the current shipments schema
    And the replica table now contains a new nullable column not in the contract
    When the Bronze transactional ingestion job runs
    Then the new column is included in the records written to Bronze
    And "schema_drift_detected" is set to True on affected records
    And a WARNING alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"
    And the job completes with status "SUCCESS_WITH_WARNINGS"

  Scenario: Column removed from the replica table (breaking change)
    Given the data contract defines column "shipment__delivery_window__start" as required
    And the replica table no longer contains that column
    When the Bronze transactional ingestion job runs
    Then the affected records are written to "swiftlogix_bronze.transactional.shipments_quarantine"
    And each quarantined record contains "violation_type" set to "MISSING_FIELD"
    And a CRITICAL alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"
    And zero affected records are written to the main shipments table

  # ---------------------------------------------------------------------------
  # Connectivity and resilience
  # ---------------------------------------------------------------------------

  Scenario: RDS read replica is temporarily unreachable
    Given the RDS read replica connection is unavailable
    When the Bronze transactional ingestion job attempts to connect
    Then the job retries with exponential backoff up to the configured maximum attempts
    And if all retries are exhausted the job fails with status "FAILED"
    And the watermark is NOT updated
    And a CRITICAL alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"
    And the failed run is recorded in "swiftlogix_observability.monitoring.pipeline_runs"

  Scenario: Large batch extraction does not impact replica query performance
    Given the replica is under normal transactional load
    When the Bronze ingestion job runs a large watermark window extraction
    Then the JDBC extraction uses a fetch size within the configured safe limit
    And the extraction is performed in parallel partitioned chunks when the batch exceeds the partition threshold

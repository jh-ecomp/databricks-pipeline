# language: en

Feature: Bronze ingestion — sorting center scan events
  As a data platform
  I want to ingest checkpoint scan events from sorting center conveyors into the Bronze layer
  So that package tracking events are available as the system of record for downstream processing

  Background:
    Given the Unity Catalog catalog "swiftlogix_bronze" exists
    And the schema "events" exists within "swiftlogix_bronze"
    And the Delta table "swiftlogix_bronze.events.sorting_center_scans" exists and is partitioned by "event_date"
    And the data contract for "sorting_center_scans" is registered in Unity Catalog
    And AWS Secrets Manager contains valid credentials for the S3 landing zone bucket

  Scenario: Ingest a valid micro-batch of sorting center scan events
    Given a set of JSON files have arrived in the S3 landing zone prefix "sorting/raw/"
    And all JSON files conform to the registered data contract schema
    When the Bronze ingestion job runs with trigger "availableNow"
    Then all scan events are written to "swiftlogix_bronze.events.sorting_center_scans"
    And each record contains the flattened fields from the original nested JSON
    And each record contains "ingestion_timestamp", "pipeline_run_id", "source", and "raw_payload"
    And "source" is set to "s3_landing_sorting"
    And the job run is recorded in "swiftlogix_observability.monitoring.pipeline_runs" with status "SUCCESS"

  Scenario: Scan events from multiple sorting centers are ingested in the same run
    Given JSON files from 3 distinct sorting centers arrive in the same S3 prefix
    And each file contains a "sorting_center__id" field identifying the source center
    When the Bronze ingestion job completes
    Then records from all 3 centers are present in "swiftlogix_bronze.events.sorting_center_scans"
    And each record retains its original "sorting_center__id" value

  Scenario: Re-running the job for the same files does not duplicate records
    Given scan events have already been ingested in a previous run
    And the same S3 files are still present in the landing zone
    When the Bronze ingestion job runs again
    Then the record count in "swiftlogix_bronze.events.sorting_center_scans" does not increase

  Scenario: Breaking schema change in sorting center scan payload triggers quarantine
    Given the data contract defines field "scan__checkpoint_id" as required
    And a new batch of JSON files contains "scan__checkpoint_code" instead, with "scan__checkpoint_id" absent
    When the Bronze ingestion job processes the batch
    Then the affected records are written to "swiftlogix_bronze.events.sorting_center_scans_quarantine"
    And each quarantined record contains "violation_type" set to "BREAKING_RENAME"
    And a CRITICAL alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"
    And zero affected records are written to the main scans table

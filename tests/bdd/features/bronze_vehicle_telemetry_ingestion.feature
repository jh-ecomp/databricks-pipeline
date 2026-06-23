# language: en

Feature: Bronze ingestion — vehicle telemetry events
  As a data platform
  I want to ingest vehicle telemetry events from the S3 landing zone into the Bronze layer
  So that GPS positions, temperature readings and status events are available as the
  system of record for all downstream processing

  Background:
    Given the Unity Catalog catalog "swiftlogix_bronze" exists
    And the schema "events" exists within "swiftlogix_bronze"
    And the Delta table "swiftlogix_bronze.events.vehicle_telemetry" exists and is partitioned by "event_date"
    And the data contract for "vehicle_telemetry" is registered in Unity Catalog
    And AWS Secrets Manager contains valid credentials for the S3 landing zone bucket

  # ---------------------------------------------------------------------------
  # Happy path — normal ingestion
  # ---------------------------------------------------------------------------

  Scenario: Ingest a valid micro-batch of telemetry events
    Given a set of JSON files have arrived in the S3 landing zone prefix "telemetry/raw/"
    And all JSON files conform to the registered data contract schema
    When the Bronze ingestion job runs with trigger "availableNow"
    Then all events are written to "swiftlogix_bronze.events.vehicle_telemetry"
    And each record contains the flattened fields from the original nested JSON
    And each record contains the metadata column "ingestion_timestamp" with the current UTC time
    And each record contains the metadata column "pipeline_run_id" matching the Databricks job run ID
    And each record contains the metadata column "source" with value "s3_landing_telemetry"
    And each record contains the column "raw_payload" with the original JSON string
    And the S3 files are NOT deleted or modified by the ingestion job
    And the job run is recorded in "swiftlogix_observability.monitoring.pipeline_runs" with status "SUCCESS"

  Scenario: Partition new records by event date
    Given telemetry events with "event_timestamp" values spanning multiple calendar dates
    When the Bronze ingestion job completes
    Then records are stored in the correct "event_date" partition for each event
    And no record is written to a partition that does not match its "event_timestamp" date

  # ---------------------------------------------------------------------------
  # Idempotency and re-executability
  # ---------------------------------------------------------------------------

  Scenario: Re-running the job for the same S3 files does not duplicate records
    Given a set of JSON files have already been ingested in a previous run
    And the same files are still present in the S3 landing zone
    When the Bronze ingestion job runs again
    Then the record count in "swiftlogix_bronze.events.vehicle_telemetry" does not increase
    And no duplicate "pipeline_run_id" + "event_id" combinations exist in the table

  Scenario: Job interrupted mid-run and restarted produces correct final state
    Given a micro-batch ingestion job was interrupted after writing 60% of the records
    When the job is restarted
    Then the final table state contains exactly the records from the full batch
    And no partial or duplicate records exist from the interrupted run

  # ---------------------------------------------------------------------------
  # Schema drift detection
  # ---------------------------------------------------------------------------

  Scenario: New optional field added to JSON payload (non-breaking change)
    Given the data contract for "vehicle_telemetry" defines the current schema
    And a new batch of JSON files contains an additional field not present in the contract
    When the Bronze ingestion job processes the batch
    Then the new field is written to "swiftlogix_bronze.events.vehicle_telemetry" as a new column
    And the record contains "schema_drift_detected" set to True
    And the record contains "schema_drift_detail" describing the new field name
    And a WARNING alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"
    And the job completes with status "SUCCESS_WITH_WARNINGS"

  Scenario: Required field renamed in JSON payload (breaking change)
    Given the data contract defines field "delivery_window__start" as required
    And a new batch of JSON files contains "delivery__window_start" instead, with "delivery_window__start" absent
    When the Bronze ingestion job processes the batch
    Then the affected records are written to "swiftlogix_bronze.events.vehicle_telemetry_quarantine"
    And each quarantined record contains "violation_type" set to "BREAKING_RENAME"
    And each quarantined record contains "violation_detail" naming both the missing and the unexpected field
    And each quarantined record contains "raw_payload" with the original JSON intact
    And zero affected records are written to "swiftlogix_bronze.events.vehicle_telemetry"
    And a CRITICAL alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"
    And the job completes with status "SUCCESS_WITH_QUARANTINE"

  Scenario: Required field missing entirely from JSON payload
    Given the data contract defines field "vehicle__id" as required
    And a new batch of JSON files contains records where "vehicle__id" is absent
    When the Bronze ingestion job processes the batch
    Then the affected records are written to "swiftlogix_bronze.events.vehicle_telemetry_quarantine"
    And each quarantined record contains "violation_type" set to "MISSING_FIELD"
    And a CRITICAL alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"

  Scenario: Field type changed incompatibly in JSON payload
    Given the data contract defines "vehicle__temp_celsius" as DOUBLE
    And a new batch contains "vehicle__temp_celsius" as a non-numeric string value
    When the Bronze ingestion job processes the batch
    Then the affected records are written to "swiftlogix_bronze.events.vehicle_telemetry_quarantine"
    And each quarantined record contains "violation_type" set to "TYPE_MISMATCH"
    And a CRITICAL alert is recorded in "swiftlogix_observability.monitoring.pipeline_alerts"

  # ---------------------------------------------------------------------------
  # Cold chain events (subset of telemetry)
  # ---------------------------------------------------------------------------

  Scenario: Temperature readings for cold chain vehicles are ingested correctly
    Given telemetry events where "vehicle__cold_chain_enabled" is True
    And events contain "vehicle__temp_celsius" readings
    When the Bronze ingestion job completes
    Then records with "vehicle__cold_chain_enabled" True are written to the main telemetry table
    And "vehicle__temp_celsius" is stored as DOUBLE with its original precision

  # ---------------------------------------------------------------------------
  # Observability
  # ---------------------------------------------------------------------------

  Scenario: Pipeline run metrics are recorded after each execution
    Given the Bronze ingestion job runs successfully
    When the job completes
    Then "swiftlogix_observability.monitoring.pipeline_runs" contains a new record with:
      | column               | value                              |
      | pipeline_name        | bronze_vehicle_telemetry           |
      | status               | SUCCESS                            |
      | records_ingested     | the count of records written       |
      | records_quarantined  | 0                                  |
      | run_duration_seconds | a positive integer                 |
      | pipeline_run_id      | the Databricks job run ID          |

  Scenario: No new files in landing zone results in a no-op run
    Given no new JSON files have arrived in the S3 landing zone since the last run
    When the Bronze ingestion job runs with trigger "availableNow"
    Then no records are written to "swiftlogix_bronze.events.vehicle_telemetry"
    And the job completes with status "SUCCESS"
    And "records_ingested" is recorded as 0 in the pipeline runs table

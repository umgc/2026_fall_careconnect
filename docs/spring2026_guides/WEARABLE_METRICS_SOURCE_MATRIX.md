# Wearable Metrics Source Matrix (Spring/Summer 2026 Semester)

## Purpose

This guide defines the semester-supported wearable metrics, maps each metric to an existing persisted model, and identifies placeholder/demo-only behavior.

## Semester Sources

- Fitbit (`fitbit`)
- Apple Health (`apple_health`, iOS)
- Health Connect (`google_fit`, Android)

## Metric Mapping Baseline (Persisted Backend Models)

- `HEART_RATE` -> `WearableMetric.metric=HEART_RATE` (`wearable_metric.metric_value`)
- `SPO2` -> `WearableMetric.metric=SPO2` (`wearable_metric.metric_value`)
- `BLOOD_PRESSURE_SYS` -> `WearableMetric.metric=BLOOD_PRESSURE_SYS` (`wearable_metric.metric_value`)
- `BLOOD_PRESSURE_DIA` -> `WearableMetric.metric=BLOOD_PRESSURE_DIA` (`wearable_metric.metric_value`)
- `STEPS` -> `WearableMetric.metric=STEPS` (`wearable_metric.metric_value`)
- Manual vitals also exist in `VitalSample` (`heartRate`, `spo2`, `systolic`, `diastolic`, `weight`) for manual-entry API flows.

## Source -> Metric Status Matrix

### Fitbit

- Steps: `Persisted mapping` (maps to `WearableMetric.STEPS`).
- Activity (calories): `Placeholder` (UI/demo only; no dedicated persisted activity entity in this story).
- Heart rate: `Placeholder` for semester implementation (mapped model exists, source sync not wired in this story).
- SpO2: `Placeholder` for semester implementation (mapped model exists, source sync not wired in this story).
- Blood pressure (systolic/diastolic): `Placeholder` for semester implementation (mapped models exist, source sync not wired in this story).

### Apple Health

- Steps: `Persisted mapping` (maps to `WearableMetric.STEPS`).
- Heart rate: `Persisted mapping` (maps to `WearableMetric.HEART_RATE`).
- Blood pressure (systolic/diastolic): `Persisted mapping` (maps to `WearableMetric.BLOOD_PRESSURE_SYS` / `BLOOD_PRESSURE_DIA`).
- SpO2: `Placeholder` (mapped model exists; collection not wired in current app flow).
- Activity (calories): `Placeholder` (UI/demo only for this story scope).
- Blood glucose: `Out of semester scope` (display-only placeholder; no persisted wearable mapping required by this story).

### Health Connect (Google Fit platform key)

- Steps: `Persisted mapping` (maps to `WearableMetric.STEPS`).
- Heart rate: `Persisted mapping` (maps to `WearableMetric.HEART_RATE`).
- Blood pressure (systolic/diastolic): `Persisted mapping` (maps to `WearableMetric.BLOOD_PRESSURE_SYS` / `BLOOD_PRESSURE_DIA`).
- SpO2: `Placeholder` (mapped model exists; collection not wired in current app flow).
- Activity (calories): `Placeholder` (UI/demo only for this story scope).
- Blood glucose: `Out of semester scope` (display-only placeholder; no persisted wearable mapping required by this story).

## Implementation Scope For This Story

- Align backend wearable metric enum to current persisted schema (`STEPS` included).
- Define and expose an explicit source-to-metric matrix in wearables UI.
- Mark placeholder/demo-only metrics explicitly in UI copy/status.
- Document source support and mapping to existing persisted entities.

## Demonstration Scope For This Semester

- Demonstrate source connection and local metric display from supported platforms.
- Demonstrate explicit status labels for persisted mapping vs placeholder behavior.
- Demonstrate documented mapping coverage for heart rate, SpO2, blood pressure, steps, and activity where available.

## Explicitly Out Of Scope (Follow-Up Story)

- New mobile-to-backend wearable ingestion APIs.
- Persistence unification between `wearable_metric` and `vital_sample`.
- End-to-end source attribution storage on vital rows.

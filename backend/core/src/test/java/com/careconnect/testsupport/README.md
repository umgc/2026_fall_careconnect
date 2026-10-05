# Backend Test Support

## Purpose

This folder contains shared fixture builders for backend unit tests.  
Its goal is to replace ad-hoc inline object setup with reusable mock data so tests remain consistent and easy to review.

## Scope

- Test-only fixture builders used by JUnit tests under `backend/core/src/test/java`.
- Stable defaults for `Task` and `Patient` entities/DTOs.
- Helpers that support mocked repository/service tests without live dependencies.

## Non-Goals

- No production code behavior changes.
- No database integration setup.
- No broad refactor of all existing tests in a single pass.

## Quick Usage

```java
import com.careconnect.testsupport.fixtures.TaskFixtures;
import com.careconnect.testsupport.fixtures.PatientFixtures;

Task task = TaskFixtures.taskWithId(42L);
Patient patient = PatientFixtures.basicPatient();
TaskDtoV2 dto = TaskFixtures.taskDtoForCreate();
```

## Ownership

Owned by the testing workstream for REQ-2.1 (Java mock data framework).

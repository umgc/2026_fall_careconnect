# Cerner allergy route and date validation

Reviewed October 13, 2026, against Team C baseline `4e5266e925c3e9cb764958fa415ec32372b9442e`.

The provisional allergy controller required service and access-policy beans that do not exist in this baseline. It could prevent the whole application context from starting. The route now stays off by default through `careconnect.cerner.allergies.enabled=false`. Set `CARECONNECT_CERNER_ALLERGIES_ENABLED=true`, or set the Spring property to true, only when real `CernerAllergyService` and `CernerAccessPolicy` beans are configured. Enabling it without either bean still fails. This change adds no production mocks or access bypass.

The mapper now checks calendar validity for year-month and full-date strings before preserving their precision. Invalid months and impossible dates are rejected. An invalid recorded date drops that record while keeping a valid sibling. Offset date-time normalization and year-only handling remain unchanged.

## Executed checks

- Before the date fix, 13 mapper tests ran: 2 failed. They showed that an invalid month and an impossible recorded date were accepted.
- After the date fix, all 49 mapper and controller tests passed.
- With the route setting added, all 54 focused tests passed: 13 mapper, 8 standalone Cerner controller, 5 configuration, and 28 existing allergy controller tests.
- The same run also selected `CallFlowIntegrationTest` and `EmailOAuthFlowE2ETest`. Overall it ran 110 tests, with no assertion failures and 56 context errors. The missing Cerner bean error was removed. Both wider suites then failed at the H2 schema patch for `ai_held_item`: H2 rejected a filtered unique index with a `WHERE` clause. Full application startup is therefore still blocked in those tests.

The five configuration tests prove default off, explicit off, enabled with both beans, and failure with each required bean missing. They use a small Spring context with mock interface beans. The existing controller tests also use mocks; they do not prove a live vendor call, database storage, real security-filter behavior, or release acceptance.

The tests used Java 17 and Maven. Local logs and JUnit evidence are retained in the course output folder. Do not treat these local checks as live Cerner or PostgreSQL evidence.

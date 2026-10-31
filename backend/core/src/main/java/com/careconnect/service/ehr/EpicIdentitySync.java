package com.careconnect.service.ehr;

import com.careconnect.ehr.reconciliation.IdentityFieldNames;
import com.careconnect.ehr.reconciliation.IdentityReconciler;
import com.careconnect.ehr.reconciliation.ReconciliationOutcome;
import com.careconnect.ehr.reconciliation.SourceIdentitySnapshot;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Feeds an Epic {@code Patient} resource's demographics into the identity reconciliation pattern —
 * Cononical_5_1 Step 7, Team E brief S6. Upserts one {@code ehr_source_identity} row per
 * {@code (patient_id, source_id)} (the reconciler's precondition) and then calls
 * {@link IdentityReconciler#reconcile}, which resolves each field against {@code patient} by the
 * recency-wins rule and may leave {@code date_of_birth} {@code PENDING} the patient's confirmation.
 *
 * <p>Works in {@code JsonNode} (the Epic connector's representation), unlike the Medicare path which
 * maps HAPI objects. Called from {@code EpicSyncService} for the mirrored Patient resource, in its
 * own transaction and wrapped by the caller's try/catch so a reconcile failure never fails the sync.
 *
 * <p><b>sourceUpdatedAt is never fabricated.</b> {@link SourceIdentitySnapshot} forbids a "now"
 * fallback — an undated snapshot would silently win every reconcile — so when the Epic Patient
 * carries no {@code meta.lastUpdated} this skips identity entirely (the row's {@code source_updated_at}
 * is NOT NULL for the same reason).
 */
@Slf4j
@Component
public class EpicIdentitySync {

    private final EhrSourceIdentityRepository identities;
    private final IdentityReconciler reconciler;

    public EpicIdentitySync(final EhrSourceIdentityRepository identities,
                            final IdentityReconciler reconciler) {
        this.identities = identities;
        this.reconciler = reconciler;
    }

    /**
     * Upsert the identity row and reconcile it. No-op when ids are unresolved or the Patient carries
     * no {@code meta.lastUpdated}.
     */
    @Transactional
    public void syncFromPatient(final Long patientId, final Long sourceId, final JsonNode patient) {
        if (patientId == null || sourceId == null || patient == null) {
            return;
        }
        final Instant sourceUpdatedAt = metaLastUpdated(patient);
        if (sourceUpdatedAt == null) {
            log.warn("Epic identity reconcile skipped for patient {}: Patient has no meta.lastUpdated "
                    + "(refusing to fabricate a provenance timestamp)", patientId);
            return;
        }

        final EhrSourceIdentity row = build(patientId, sourceId, sourceUpdatedAt, patient);
        identities.findByPatientIdAndSourceId(patientId, sourceId)
                .ifPresent(existing -> row.setId(existing.getId()));
        identities.save(row);

        final Map<String, String> fields = reconciledFields(row);
        if (fields.isEmpty()) {
            return;
        }
        final List<ReconciliationOutcome> outcomes =
                reconciler.reconcile(new SourceIdentitySnapshot(patientId, sourceId, sourceUpdatedAt, fields));
        for (final ReconciliationOutcome outcome : outcomes) {
            if (outcome != null && outcome.decision() == ReconciliationOutcome.Decision.PENDING_PATIENT_CONFIRMATION) {
                log.info("Epic identity: date_of_birth PENDING patient confirmation for patient {} "
                        + "(resolve via POST /v1/api/ehr/identity-conflicts/{id}/resolve)", patientId);
            }
        }
    }

    /** Build the identity row from the Epic Patient JSON (all stored fields, reconciled or not). */
    private static EhrSourceIdentity build(final Long patientId, final Long sourceId,
                                           final Instant sourceUpdatedAt, final JsonNode patient) {
        final JsonNode name = firstOf(patient, "name");
        final JsonNode address = firstOf(patient, "address");
        String phone = null;
        String email = null;
        final JsonNode telecom = patient.get("telecom");
        if (telecom != null && telecom.isArray()) {
            for (final JsonNode cp : telecom) {
                final String system = text(cp, "system");
                if ("phone".equalsIgnoreCase(system) && phone == null) {
                    phone = text(cp, "value");
                } else if ("email".equalsIgnoreCase(system) && email == null) {
                    email = text(cp, "value");
                }
            }
        }
        return EhrSourceIdentity.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .sourceUpdatedAt(sourceUpdatedAt)
                .givenName(givenName(name))
                .familyName(text(name, "family"))
                .dateOfBirth(fullDate(text(patient, "birthDate")))
                .gender(text(patient, "gender"))
                .phone(phone)
                .email(email)
                .addressLine1(line(address, 0))
                .addressLine2(line(address, 1))
                .city(text(address, "city"))
                .state(text(address, "state"))
                .postalCode(text(address, "postalCode"))
                .managingOrg(text(patient.get("managingOrganization"), "display"))
                .language(language(patient))
                .memberId(text(firstOf(patient, "identifier"), "value"))
                .build();
    }

    /** The reconciled subset (the 10 names in {@link IdentityFieldNames#ALL}), non-blank only. */
    private static Map<String, String> reconciledFields(final EhrSourceIdentity r) {
        final Map<String, String> fields = new LinkedHashMap<>();
        put(fields, IdentityFieldNames.GIVEN_NAME, r.getGivenName());
        put(fields, IdentityFieldNames.FAMILY_NAME, r.getFamilyName());
        put(fields, IdentityFieldNames.DATE_OF_BIRTH, r.getDateOfBirth() == null ? null : r.getDateOfBirth().toString());
        put(fields, IdentityFieldNames.PHONE, r.getPhone());
        put(fields, IdentityFieldNames.EMAIL, r.getEmail());
        put(fields, IdentityFieldNames.ADDRESS_LINE1, r.getAddressLine1());
        put(fields, IdentityFieldNames.ADDRESS_LINE2, r.getAddressLine2());
        put(fields, IdentityFieldNames.CITY, r.getCity());
        put(fields, IdentityFieldNames.STATE, r.getState());
        put(fields, IdentityFieldNames.POSTAL_CODE, r.getPostalCode());
        return fields;
    }

    private static void put(final Map<String, String> map, final String key, final String value) {
        if (value != null && !value.isBlank()) {
            map.put(key, value);
        }
    }

    // --- JSON helpers ---

    private static String givenName(final JsonNode name) {
        if (name == null) {
            return null;
        }
        final JsonNode given = name.get("given");
        if (given == null || !given.isArray() || given.isEmpty()) {
            return null;
        }
        final StringBuilder sb = new StringBuilder();
        for (final JsonNode g : given) {
            if (sb.length() > 0) {
                sb.append(' ');
            }
            sb.append(g.asText());
        }
        return sb.length() > 0 ? sb.toString() : null;
    }

    private static String line(final JsonNode address, final int idx) {
        if (address == null) {
            return null;
        }
        final JsonNode lines = address.get("line");
        return lines != null && lines.isArray() && lines.size() > idx ? lines.get(idx).asText() : null;
    }

    private static String language(final JsonNode patient) {
        final JsonNode comm = firstOf(patient, "communication");
        final JsonNode lang = comm == null ? null : comm.get("language");
        if (lang == null) {
            return null;
        }
        if (lang.hasNonNull("text")) {
            return lang.get("text").asText();
        }
        final JsonNode coding = firstOf(lang, "coding");
        return coding != null && coding.hasNonNull("display") ? coding.get("display").asText() : null;
    }

    /** FHIR birthDate only when it is a full calendar date; FHIR allows year- or month-only. */
    private static LocalDate fullDate(final String value) {
        if (value == null || value.length() != 10 || !value.matches("\\d{4}-\\d{2}-\\d{2}")) {
            return null;
        }
        try {
            return LocalDate.parse(value);
        } catch (final RuntimeException ignored) {
            return null;
        }
    }

    private static Instant metaLastUpdated(final JsonNode patient) {
        final JsonNode meta = patient.get("meta");
        if (meta != null && meta.hasNonNull("lastUpdated")) {
            try {
                return OffsetDateTime.parse(meta.get("lastUpdated").asText()).toInstant();
            } catch (final RuntimeException ignored) {
                return null;
            }
        }
        return null;
    }

    private static String text(final JsonNode node, final String field) {
        if (node == null) {
            return null;
        }
        final JsonNode v = node.get(field);
        return v != null && !v.isNull() ? v.asText() : null;
    }

    private static JsonNode firstOf(final JsonNode node, final String arrayField) {
        if (node == null) {
            return null;
        }
        final JsonNode arr = node.get(arrayField);
        return arr != null && arr.isArray() && !arr.isEmpty() ? arr.get(0) : null;
    }
}

package com.careconnect.ehr.reconciliation.jpa;

import com.careconnect.ehr.reconciliation.PatientFieldAccessor;
import com.careconnect.model.Address;
import com.careconnect.model.Patient;
import com.careconnect.repository.PatientRepository;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.time.format.ResolverStyle;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.function.BiConsumer;
import java.util.function.Function;

/**
 * Reads and writes {@code patient} on behalf of the reconciliation library.
 *
 * <h2>Two vocabularies</h2>
 * The library names fields the way {@code ehr_source_identity} and FHIR do — {@code given_name},
 * {@code family_name}, {@code postal_code}. {@code Patient} names them the way this codebase grew —
 * {@code firstName}, {@code lastName}, and an embedded {@link Address} whose column is {@code zip}.
 * This class is the only place those two vocabularies meet, deliberately: adapters should never
 * have to know {@code Patient}'s field names, and {@code Patient} should not be renamed to suit the
 * EHR work.
 *
 * <p>An unrecognised field name is rejected rather than skipped. Silently ignoring it would mean an
 * adapter could send {@code firstName} instead of {@code given_name}, see no error, and quietly
 * reconcile nothing at all for that field — forever.
 *
 * <h2>Empty means empty</h2>
 * {@link #getCurrentValue} returns {@link Optional#empty()} for a value that is null <em>or
 * blank</em>. The distinction matters more than it looks: the algorithm fills an empty field
 * directly, with no timestamp comparison and no audit row, so treating {@code ""} as a real value
 * would turn "this patient has no phone number on file" into a disagreement to be adjudicated, and
 * could hold a genuine incoming value out on a timestamp technicality.
 *
 * <h2>date_of_birth is text</h2>
 * {@code Patient.dob} is a {@code varchar}, not a date column. Writes are parsed as ISO-8601 before
 * being stored, so this class cannot be the thing that puts an unparseable date in there; reads
 * return whatever is already stored, unvalidated, because legacy rows are not this class's to
 * reinterpret. A legacy value in some other format will read as a disagreement with an incoming
 * ISO one — which, for {@code date_of_birth}, means the patient gets asked rather than anything
 * being overwritten. That is the right failure for bad data to have.
 *
 * <h2>The timestamp zone</h2>
 * {@code Auditable} stores {@code LocalDateTime} into a {@code timestamp without time zone} column,
 * so the instant it denotes depends on the writing JVM's zone. {@link #getPatientUpdatedAt} resolves
 * it with {@link ZoneId#systemDefault()}, which round-trips correctly as long as the application
 * writes and reads in the same zone — true today, and the same assumption every other
 * {@code Auditable} entity already makes. It is worth knowing that a server whose zone changes
 * would shift this baseline, because this particular value decides who wins a reconciliation.
 */
public class JpaPatientFieldAccessor implements PatientFieldAccessor {

    /** The onboarding registration screen's date shape; STRICT so 02/30/1950 is not silently rolled. */
    private static final DateTimeFormatter US_DATE =
            DateTimeFormatter.ofPattern("MM/dd/uuuu").withResolverStyle(ResolverStyle.STRICT);

    /**
     * One entry per field the library may reconcile. Held as an ordered map purely so the error
     * message for an unknown field can list the supported names in a stable order.
     */
    private static final Map<String, FieldBinding> BINDINGS = bindings();

    private final PatientRepository patientRepository;

    public JpaPatientFieldAccessor(PatientRepository patientRepository) {
        this.patientRepository = Objects.requireNonNull(patientRepository, "patientRepository");
    }

    /** The field names this accessor understands, for callers that want to check before sending. */
    public static Set<String> supportedFieldNames() {
        return BINDINGS.keySet();
    }

    @Override
    public Optional<String> getCurrentValue(Long patientId, String fieldName) {
        FieldBinding binding = bindingFor(fieldName);
        Patient patient = require(patientId);
        String value = binding.read().apply(patient);
        return (value == null || value.isBlank()) ? Optional.empty() : Optional.of(value);
    }

    @Override
    public Instant getPatientUpdatedAt(Long patientId) {
        Patient patient = require(patientId);
        LocalDateTime updatedAt = patient.getUpdatedAt();
        if (updatedAt == null) {
            // Not a recoverable "unknown": the algorithm would have to invent a baseline, and either
            // choice silently decides reconciliations. Every row should have been backfilled by
            // SchemaPatchRunner V2609291230b, so a null here means that patch did not run.
            throw new IllegalStateException(
                    "patient " + patient.getId() + " has no updated_at, so there is no reconciliation "
                            + "baseline for a field with no provenance. Expected SchemaPatchRunner "
                            + "V2609291230b to have backfilled it.");
        }
        return updatedAt.atZone(ZoneId.systemDefault()).toInstant();
    }

    /**
     * Writes the value through and lets the surrounding transaction flush it. The write bumps
     * {@code patient.updated_at} via {@code Auditable}'s {@code @PreUpdate}, which is correct — the
     * record did change — but see {@code getPatientUpdatedAt}: that same column is the baseline for
     * any field which has no provenance row yet, so applying one field raises the bar for the others
     * until each has provenance of its own.
     */
    @Override
    public void applyValue(Long patientId, String fieldName, String newValue) {
        requireTransaction();
        FieldBinding binding = bindingFor(fieldName);
        Objects.requireNonNull(newValue, "newValue");
        Patient patient = require(patientId);
        binding.write().accept(patient, binding.normalise().apply(newValue));
        patientRepository.save(patient);
    }

    private Patient require(Long patientId) {
        Long id = Objects.requireNonNull(patientId, "patientId");
        return patientRepository.findById(id).orElseThrow(() -> new IllegalArgumentException(
                "No patient with id " + id + " to reconcile against"));
    }

    private static FieldBinding bindingFor(String fieldName) {
        Objects.requireNonNull(fieldName, "fieldName");
        FieldBinding binding = BINDINGS.get(fieldName);
        if (binding == null) {
            throw new IllegalArgumentException(
                    "Unknown identity field '" + fieldName + "'. This accessor understands "
                            + BINDINGS.keySet() + ". Adapters must use the ehr_source_identity "
                            + "column names, not Patient's Java field names.");
        }
        return binding;
    }

    private static void requireTransaction() {
        if (!TransactionSynchronizationManager.isActualTransactionActive()) {
            throw new IllegalStateException(
                    "PatientFieldAccessor.applyValue requires an active transaction, so the write "
                            + "commits or rolls back together with the provenance row and audit row "
                            + "decided alongside it.");
        }
    }

    /**
     * How one library field name maps onto {@code Patient}.
     *
     * @param read      pulls the current value out, or null if unset.
     * @param write     puts a value in, creating the embedded {@link Address} if that is where it
     *                  lives and the patient has none yet.
     * @param normalise validates and canonicalises an incoming value before it is stored.
     */
    private record FieldBinding(
            Function<Patient, String> read,
            BiConsumer<Patient, String> write,
            Function<String, String> normalise) {
    }

    private static Map<String, FieldBinding> bindings() {
        Map<String, FieldBinding> map = new LinkedHashMap<>();
        map.put("given_name", simple(Patient::getFirstName, Patient::setFirstName));
        map.put("family_name", simple(Patient::getLastName, Patient::setLastName));
        map.put("date_of_birth", new FieldBinding(
                patient -> storedDobAsIso(patient.getDob()), Patient::setDob, JpaPatientFieldAccessor::requireIsoDate));
        map.put("phone", simple(Patient::getPhone, Patient::setPhone));
        map.put("email", simple(Patient::getEmail, Patient::setEmail));
        map.put("address_line1", address(Address::getLine1, Address::setLine1));
        map.put("address_line2", address(Address::getLine2, Address::setLine2));
        map.put("city", address(Address::getCity, Address::setCity));
        map.put("state", address(Address::getState, Address::setState));
        map.put("postal_code", address(Address::getZip, Address::setZip));
        // Collections.unmodifiableMap, not Map.copyOf: the latter returns an unordered map, which
        // would quietly defeat the insertion order this map is built in and the stable listing the
        // unknown-field error message depends on.
        return Collections.unmodifiableMap(map);
    }

    private static FieldBinding simple(
            Function<Patient, String> read, BiConsumer<Patient, String> write) {
        return new FieldBinding(read, write, String::trim);
    }

    private static FieldBinding address(
            Function<Address, String> read, BiConsumer<Address, String> write) {
        return new FieldBinding(
                patient -> patient.getAddress() == null ? null : read.apply(patient.getAddress()),
                (patient, value) -> {
                    if (patient.getAddress() == null) {
                        patient.setAddress(new Address());
                    }
                    write.accept(patient.getAddress(), value);
                },
                String::trim);
    }

    /**
     * patient.dob is free text, and the app writes it in two shapes: the onboarding registration
     * screen stores MM/DD/YYYY, the sign-up screen stores ISO. A FHIR birthDate is always ISO, so
     * the stored value is compared in ISO form; otherwise the same date "disagrees" and opens a
     * patient confirmation for a date that did not change (DEF-EHR-REC-03). Read-side only: the
     * stored value is not rewritten. Anything that is neither shape is returned as stored, so a
     * genuinely different value is still a disagreement.
     */
    private static String storedDobAsIso(String stored) {
        if (stored == null || stored.isBlank()) {
            return stored;
        }
        String trimmed = stored.trim();
        try {
            return LocalDate.parse(trimmed).toString();
        } catch (DateTimeParseException notIso) {
            try {
                return LocalDate.parse(trimmed, US_DATE).toString();
            } catch (DateTimeParseException notUs) {
                return stored;
            }
        }
    }

    /**
     * {@code patient.dob} is a varchar and will accept anything. Since this class is the only writer
     * the reconciliation path has, validating here is what keeps a malformed source value from
     * becoming a permanently unparseable date of birth.
     */
    private static String requireIsoDate(String value) {
        String trimmed = value.trim();
        try {
            return LocalDate.parse(trimmed).toString();
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException(
                    "date_of_birth must be an ISO-8601 date (yyyy-MM-dd), got: " + value, e);
        }
    }
}

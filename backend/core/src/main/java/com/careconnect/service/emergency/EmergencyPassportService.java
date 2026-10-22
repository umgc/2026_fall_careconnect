package com.careconnect.service.emergency;

import com.careconnect.dto.emergency.PassportDtos.AllergyItem;
import com.careconnect.dto.emergency.PassportDtos.EmergencyContact;
import com.careconnect.dto.emergency.PassportDtos.MedicationItem;
import com.careconnect.dto.emergency.PassportDtos.NewTokenResponse;
import com.careconnect.dto.emergency.PassportDtos.PassportView;
import com.careconnect.dto.emergency.PassportDtos.ProfileRequest;
import com.careconnect.dto.emergency.PassportDtos.PublicPassport;
import com.careconnect.dto.emergency.PassportDtos.TokenStatus;
import com.careconnect.exception.AppException;
import com.careconnect.model.Allergy;
import com.careconnect.model.Medication;
import com.careconnect.model.Patient;
import com.careconnect.model.emergency.EmergencyPassportFieldVisibility;
import com.careconnect.model.emergency.EmergencyPassportProfile;
import com.careconnect.model.emergency.EmergencyPassportToken;
import com.careconnect.model.emergency.PassportField;
import com.careconnect.repository.AllergyRepository;
import com.careconnect.repository.MedicationRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.emergency.EmergencyPassportFieldVisibilityRepository;
import com.careconnect.repository.emergency.EmergencyPassportProfileRepository;
import com.careconnect.repository.emergency.EmergencyPassportTokenRepository;
import com.careconnect.security.TokenHashService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.Period;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Stream;

/**
 * The Emergency Care Passport (CC-12, Increment 2): the patient's own view and edits, the QR code's
 * lifecycle, and the public scan.
 * <p>
 * Codes follow {@code InviteTokenService}: a 256-bit URL-safe random token, of which the first 16
 * characters are a non-secret lookup key and the whole is BCrypt-hashed. An unknown lookup returns
 * before any hashing, so a flood of made-up codes costs a single indexed read each.
 * <p>
 * A scan shows the patient's name and age always, so a responder can match the passport to the
 * person, and otherwise only the sections the patient made public. Birth date and city are never
 * shown. Medications are the patient's active, <em>approved</em> ones.
 */
@Slf4j
@Service
@Transactional
public class EmergencyPassportService {

    static final int LOOKUP_LENGTH = 16;
    /** The raw token is 43 characters; anything far outside that is rejected before a lookup. */
    private static final int MAX_TOKEN_LENGTH = 128;
    private static final SecureRandom RANDOM = new SecureRandom();
    /** The registration screen sends MM/DD/YYYY; seed data and older rows use ISO dates. */
    private static final DateTimeFormatter US_DATE = DateTimeFormatter.ofPattern("MM/dd/uuuu");
    private static final String APPROVED = "APPROVED";
    /** The sections stored on the one profile row, and so dated by its single updated_at. */
    private static final Set<PassportField> PROFILE_SECTIONS = Set.of(
            PassportField.BLOOD_TYPE, PassportField.CHRONIC_CONDITIONS, PassportField.EMERGENCY_CONTACT);

    static final int MAX_CHRONIC_CONDITIONS = 2000;
    static final int MAX_CONTACT_NAME = 255;
    static final int MAX_CONTACT_PHONE = 32;
    static final int MAX_CONTACT_RELATIONSHIP = 64;

    private final EmergencyPassportProfileRepository profiles;
    private final EmergencyPassportFieldVisibilityRepository visibility;
    private final EmergencyPassportTokenRepository tokens;
    private final PatientRepository patients;
    private final AllergyRepository allergies;
    private final MedicationRepository medications;
    private final TokenHashService tokenHashService;
    private final String scanBaseUrl;
    private final Clock clock;

    @Autowired
    public EmergencyPassportService(
            final EmergencyPassportProfileRepository profiles,
            final EmergencyPassportFieldVisibilityRepository visibility,
            final EmergencyPassportTokenRepository tokens,
            final PatientRepository patients,
            final AllergyRepository allergies,
            final MedicationRepository medications,
            final TokenHashService tokenHashService,
            @Value("${careconnect.passport.base-url:${frontend.base-url}/#/passport}") final String scanBaseUrl) {
        this(profiles, visibility, tokens, patients, allergies, medications, tokenHashService, scanBaseUrl,
                Clock.systemUTC());
    }

    EmergencyPassportService(
            final EmergencyPassportProfileRepository profiles,
            final EmergencyPassportFieldVisibilityRepository visibility,
            final EmergencyPassportTokenRepository tokens,
            final PatientRepository patients,
            final AllergyRepository allergies,
            final MedicationRepository medications,
            final TokenHashService tokenHashService,
            final String scanBaseUrl,
            final Clock clock) {
        this.profiles = profiles;
        this.visibility = visibility;
        this.tokens = tokens;
        this.patients = patients;
        this.allergies = allergies;
        this.medications = medications;
        this.tokenHashService = tokenHashService;
        this.scanBaseUrl = scanBaseUrl;
        this.clock = clock;
    }

    // ---- The patient's own passport ------------------------------------------------------------

    @Transactional(readOnly = true)
    public PassportView getPassport(final Long patientId) {
        final Patient patient = requirePatient(patientId);
        final Optional<EmergencyPassportProfile> profile = profiles.findByPatientId(patientId);
        final Set<PassportField> shared = visibility.findPublicFields(patientId);
        final Map<PassportField, Boolean> sharing = new EnumMap<>(PassportField.class);
        for (final PassportField field : PassportField.values()) {
            sharing.put(field, shared.contains(field));
        }
        final Optional<EmergencyPassportToken> active = activeToken(patientId);
        final TokenStatus token = active
                .map(t -> new TokenStatus(true, toInstant(t), t.getLastScannedAt()))
                .orElse(null);
        final List<Allergy> allergyRows = allergies.findActiveAllergiesByPatientId(patientId);
        final List<Medication> medicationRows = approvedMedications(patientId);
        final Map<PassportField, Instant> updated = sectionDates(profile, allergyRows, medicationRows);
        return new PassportView(
                displayName(patient),
                ageOf(patient.getDob()),
                profile.map(EmergencyPassportProfile::getBloodType).orElse(null),
                profile.map(EmergencyPassportProfile::getChronicConditions).orElse(null),
                profile.map(EmergencyPassportService::contactOf).orElse(null),
                allergyItems(allergyRows),
                medicationItems(medicationRows),
                sharing,
                token,
                active.isPresent() && !shared.isEmpty(),
                latest(updated.values().stream()).orElse(null),
                updated);
    }

    /** Replaces every patient-entered field. Blank strings are stored as null. */
    public PassportView updateProfile(final Long patientId, final ProfileRequest request) {
        requirePatient(patientId);
        if (request == null) {
            throw new AppException(HttpStatus.BAD_REQUEST, "Request body is required");
        }
        final EmergencyPassportProfile profile = profiles.findByPatientId(patientId)
                .orElseGet(() -> EmergencyPassportProfile.builder().patientId(patientId).build());
        profile.setBloodType(request.bloodType());
        profile.setChronicConditions(clean(request.chronicConditions(), MAX_CHRONIC_CONDITIONS, "chronicConditions"));
        profile.setEmergencyContactName(clean(request.emergencyContactName(), MAX_CONTACT_NAME, "emergencyContactName"));
        profile.setEmergencyContactRelationship(clean(request.emergencyContactRelationship(),
                MAX_CONTACT_RELATIONSHIP, "emergencyContactRelationship"));
        profile.setEmergencyContactPhone(clean(request.emergencyContactPhone(), MAX_CONTACT_PHONE, "emergencyContactPhone"));
        profiles.save(profile);
        return getPassport(patientId);
    }

    public PassportView setVisibility(final Long patientId, final PassportField field, final boolean isPublic) {
        requirePatient(patientId);
        final EmergencyPassportFieldVisibility row = visibility.findByPatientIdAndFieldKey(patientId, field)
                .orElseGet(() -> EmergencyPassportFieldVisibility.builder().patientId(patientId).fieldKey(field).build());
        row.setIsPublic(isPublic);
        visibility.save(row);
        return getPassport(patientId);
    }

    // ---- The QR code ---------------------------------------------------------------------------

    /**
     * Makes a new code and revokes any active one in the same transaction, so a lost phone or
     * screenshot stops working the moment the patient replaces it.
     */
    public NewTokenResponse regenerateToken(final Long patientId) {
        requirePatient(patientId);
        // Flushed before the insert: Hibernate orders inserts ahead of updates, and the partial
        // unique index allows only one ACTIVE row per patient.
        revokeActive(patientId);

        final String rawToken = generateRawToken();
        final EmergencyPassportToken token = tokens.saveAndFlush(EmergencyPassportToken.builder()
                .patientId(patientId)
                .tokenLookup(rawToken.substring(0, LOOKUP_LENGTH))
                .tokenHash(tokenHashService.hashToken(rawToken))
                .status(EmergencyPassportToken.Status.ACTIVE)
                .build());
        log.info("Emergency passport code created: tokenId={}, patientId={}", token.getId(), patientId);
        return new NewTokenResponse(rawToken, scanBaseUrl + "/" + rawToken, toInstant(token));
    }

    /** Stops sharing without making a new code. Idempotent. */
    public void revokeToken(final Long patientId) {
        requirePatient(patientId);
        revokeActive(patientId);
    }

    // ---- The public scan -----------------------------------------------------------------------

    /**
     * What a scan of {@code rawToken} shows, or empty when the code is unknown, malformed, wrong or
     * revoked. Those cases are deliberately indistinguishable to the caller.
     */
    public Optional<PublicPassport> scan(final String rawToken) {
        final Optional<EmergencyPassportToken> resolved = resolveActive(rawToken);
        if (resolved.isEmpty()) {
            return Optional.empty();
        }
        final EmergencyPassportToken token = resolved.get();
        final Optional<Patient> patient = patients.findById(token.getPatientId());
        if (patient.isEmpty()) {
            return Optional.empty();
        }
        token.setLastScannedAt(clock.instant());
        tokens.save(token);

        final Long patientId = token.getPatientId();
        final Set<PassportField> shared = visibility.findPublicFields(patientId);
        final Optional<EmergencyPassportProfile> profile = profiles.findByPatientId(patientId);
        // Hidden lists are never read, so they cannot leak into the response or its date.
        final List<Allergy> allergyRows = shared.contains(PassportField.ALLERGIES)
                ? allergies.findActiveAllergiesByPatientId(patientId) : List.of();
        final List<Medication> medicationRows = shared.contains(PassportField.MEDICATIONS)
                ? approvedMedications(patientId) : List.of();
        final Map<PassportField, Instant> dates = sectionDates(profile, allergyRows, medicationRows);
        // Blood type, conditions and contact share the profile row's updated_at. When one of them has content
        // but is hidden, that date may be an edit to the hidden one, so the scan leaves it out (DEF-EMG-04).
        if (PROFILE_SECTIONS.stream().anyMatch(field -> dates.containsKey(field) && !shared.contains(field))) {
            PROFILE_SECTIONS.forEach(dates::remove);
        }
        final Instant lastUpdated = latest(dates.entrySet().stream()
                .filter(section -> shared.contains(section.getKey()))
                .map(Map.Entry::getValue)).orElse(null);
        return Optional.of(new PublicPassport(
                displayName(patient.get()),
                ageOf(patient.get().getDob()),
                shared.contains(PassportField.BLOOD_TYPE)
                        ? profile.map(EmergencyPassportProfile::getBloodType).orElse(null) : null,
                nonEmpty(allergyItems(allergyRows)),
                nonEmpty(medicationItems(medicationRows)),
                shared.contains(PassportField.CHRONIC_CONDITIONS)
                        ? profile.map(EmergencyPassportProfile::getChronicConditions).orElse(null) : null,
                shared.contains(PassportField.EMERGENCY_CONTACT)
                        ? profile.map(EmergencyPassportService::contactOf).orElse(null) : null,
                lastUpdated));
    }

    // ---- Helpers -------------------------------------------------------------------------------

    private Optional<EmergencyPassportToken> resolveActive(final String rawToken) {
        if (rawToken == null || rawToken.length() < LOOKUP_LENGTH || rawToken.length() > MAX_TOKEN_LENGTH) {
            return Optional.empty();
        }
        return tokens.findByTokenLookup(rawToken.substring(0, LOOKUP_LENGTH))
                .filter(EmergencyPassportToken::isActive)
                .filter(t -> tokenHashService.verifyToken(rawToken, t.getTokenHash()));
    }

    private Optional<EmergencyPassportToken> activeToken(final Long patientId) {
        return tokens.findByPatientIdAndStatus(patientId, EmergencyPassportToken.Status.ACTIVE).stream().findFirst();
    }

    private void revokeActive(final Long patientId) {
        final List<EmergencyPassportToken> active =
                tokens.findByPatientIdAndStatus(patientId, EmergencyPassportToken.Status.ACTIVE);
        if (active.isEmpty()) {
            return;
        }
        final Instant now = clock.instant();
        for (final EmergencyPassportToken token : active) {
            token.setStatus(EmergencyPassportToken.Status.REVOKED);
            token.setRevokedAt(now);
        }
        tokens.saveAllAndFlush(active);
        log.info("Emergency passport code revoked: patientId={}, count={}", patientId, active.size());
    }

    private Patient requirePatient(final Long patientId) {
        return patients.findById(patientId)
                .orElseThrow(() -> new AppException(HttpStatus.NOT_FOUND, "Patient not found"));
    }

    private List<Medication> approvedMedications(final Long patientId) {
        return medications.findActiveByPatientId(patientId).stream()
                .filter(m -> APPROVED.equals(m.getApprovalStatus()))
                .toList();
    }

    private static List<AllergyItem> allergyItems(final List<Allergy> rows) {
        return rows.stream().map(EmergencyPassportService::allergyItem).toList();
    }

    private static List<MedicationItem> medicationItems(final List<Medication> rows) {
        return rows.stream()
                .map(m -> new MedicationItem(m.getMedicationName(), m.getDosage(), m.getFrequency()))
                .toList();
    }

    /**
     * When each section with content last changed, from the rows that section is built from. A
     * section with no content has no entry, so an empty section never makes the passport look fresh.
     * Only the rows shown count: an allergy or medication that was removed or never approved does not.
     */
    private static Map<PassportField, Instant> sectionDates(
            final Optional<EmergencyPassportProfile> profile,
            final List<Allergy> allergyRows,
            final List<Medication> medicationRows) {
        final Map<PassportField, Instant> dates = new EnumMap<>(PassportField.class);
        profile.ifPresent(p -> {
            final Instant changed = toInstant(p.getUpdatedAt() != null ? p.getUpdatedAt() : p.getCreatedAt());
            if (changed == null) {
                return;
            }
            if (p.getBloodType() != null) {
                dates.put(PassportField.BLOOD_TYPE, changed);
            }
            if (p.getChronicConditions() != null) {
                dates.put(PassportField.CHRONIC_CONDITIONS, changed);
            }
            if (contactOf(p) != null) {
                dates.put(PassportField.EMERGENCY_CONTACT, changed);
            }
        });
        latest(allergyRows.stream().map(a -> a.getUpdatedAt() != null ? a.getUpdatedAt() : a.getCreatedAt()))
                .ifPresent(changed -> dates.put(PassportField.ALLERGIES, changed));
        latest(medicationRows.stream().map(m -> m.getUpdatedAt() != null ? m.getUpdatedAt() : m.getCreatedAt()))
                .ifPresent(changed -> dates.put(PassportField.MEDICATIONS, changed));
        return dates;
    }

    private static Optional<Instant> latest(final Stream<Instant> dates) {
        return dates.filter(Objects::nonNull).max(Comparator.naturalOrder());
    }

    private static AllergyItem allergyItem(final Allergy allergy) {
        return new AllergyItem(
                allergy.getAllergen(),
                allergy.getSeverity() != null ? allergy.getSeverity().name() : null,
                allergy.getReaction());
    }

    private static EmergencyContact contactOf(final EmergencyPassportProfile profile) {
        if (profile.getEmergencyContactName() == null && profile.getEmergencyContactPhone() == null) {
            return null;
        }
        return new EmergencyContact(
                profile.getEmergencyContactName(),
                profile.getEmergencyContactRelationship(),
                profile.getEmergencyContactPhone());
    }

    private static <T> List<T> nonEmpty(final List<T> items) {
        return items.isEmpty() ? null : items;
    }

    private static String displayName(final Patient patient) {
        final String first = patient.getFirstName() == null ? "" : patient.getFirstName().trim();
        final String last = patient.getLastName() == null ? "" : patient.getLastName().trim();
        return (first + " " + last).trim();
    }

    /** Null when the stored date of birth is missing or in neither known format. */
    Integer ageOf(final String dob) {
        if (dob == null || dob.isBlank()) {
            return null;
        }
        final LocalDate today = LocalDate.now(clock);
        for (final DateTimeFormatter format : new DateTimeFormatter[]{DateTimeFormatter.ISO_LOCAL_DATE, US_DATE}) {
            try {
                final LocalDate born = LocalDate.parse(dob.trim(), format);
                return born.isAfter(today) ? null : Period.between(born, today).getYears();
            } catch (DateTimeParseException ignored) {
                // try the next format
            }
        }
        return null;
    }

    private static String clean(final String value, final int maxLength, final String field) {
        if (value == null || value.isBlank()) {
            return null;
        }
        final String trimmed = value.trim();
        if (trimmed.length() > maxLength) {
            throw new AppException(HttpStatus.BAD_REQUEST, field + " must be at most " + maxLength + " characters");
        }
        return trimmed;
    }

    /** {@code Auditable} stamps {@code LocalDateTime.now()}, which is in the JVM's default zone. */
    private static Instant toInstant(final EmergencyPassportToken token) {
        return toInstant(token.getCreatedAt());
    }

    private static Instant toInstant(final LocalDateTime auditStamp) {
        return auditStamp == null ? null : auditStamp.atZone(ZoneId.systemDefault()).toInstant();
    }

    private static String generateRawToken() {
        final byte[] bytes = new byte[32]; // 256 bits
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
}

package com.careconnect.service;

import com.careconnect.model.UserFile;
import com.careconnect.model.forms.FormDefinition;
import com.careconnect.model.forms.FormSchema;
import com.careconnect.model.forms.FormSubmission;
import com.careconnect.model.forms.FormType;
import com.careconnect.repository.FormDefinitionRepository;
import com.careconnect.repository.FormSubmissionRepository;
import com.careconnect.security.TokenCryptor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Validates and persists completed hiring/onboarding form submissions.
 * <p>
 * A submission is accepted only when its captured values satisfy the form's
 * declared required-status and validation rules. Each stored
 * {@link FormSubmission} references the {@link FormDefinition} version it was
 * completed against, so the schema and the captured data stay linked.
 */
@Service
@Transactional
public class FormSubmissionService {

    private static final Logger log = LoggerFactory.getLogger(FormSubmissionService.class);

    private final FormSchemaService schemaService;
    private final FormDefinitionRepository definitionRepository;
    private final FormSubmissionRepository submissionRepository;
    private final FormPdfService pdfService;
    private final FileManagementService fileManagementService;
    private final TokenCryptor tokenCryptor;

    public FormSubmissionService(FormSchemaService schemaService,
                                 FormDefinitionRepository definitionRepository,
                                 FormSubmissionRepository submissionRepository,
                                 FormPdfService pdfService,
                                 FileManagementService fileManagementService,
                                 TokenCryptor tokenCryptor) {
        this.schemaService = schemaService;
        this.definitionRepository = definitionRepository;
        this.submissionRepository = submissionRepository;
        this.pdfService = pdfService;
        this.fileManagementService = fileManagementService;
        this.tokenCryptor = tokenCryptor;
    }

    /**
     * Outcome of a submission attempt: either a persisted {@link FormSubmission}
     * or a non-empty list of human-readable validation errors.
     */
    public record SubmissionResult(FormSubmission submission, List<String> errors) {
        public boolean isValid() {
            return errors == null || errors.isEmpty();
        }
    }

    /**
     * Validate the captured values against the form's schema and, when valid,
     * persist a SUBMITTED {@link FormSubmission} owned by {@code ownerId}.
     *
     * @throws IllegalArgumentException if no bundled definition matches the
     *                                  requested form type/version.
     */
    public SubmissionResult submit(FormType formType,
                                   String version,
                                   Long ownerId,
                                   UserFile.OwnerType ownerType,
                                   Long patientId,
                                   Map<String, Object> fieldValues) {
        FormSchema schema = schemaService.loadBundledSchema(formType, version)
                .orElseThrow(() -> new IllegalArgumentException(
                        "Unknown form: " + formType + (version != null ? " v" + version : "")));

        // Drop any keys not defined by the schema so arbitrary client-supplied
        // data is never validated or persisted.
        Map<String, Object> values = schemaService.retainKnownKeys(schema, fieldValues);

        List<String> errors = schemaService.validateSubmission(schema, values);
        if (!errors.isEmpty()) {
            return new SubmissionResult(null, errors);
        }

        FormDefinition definition = resolveDefinition(schema);

        // Encrypt sensitive (PII/PHI) values before persistence; only ciphertext
        // is ever written to the database.
        Map<String, Object> storedValues =
                encryptSensitive(values, schemaService.sensitiveKeys(schema));

        FormSubmission submission = FormSubmission.builder()
                .formDefinitionId(definition.getId())
                .formType(formType)
                .formVersion(schema.getVersion())
                .ownerId(ownerId)
                .ownerType(ownerType)
                .patientId(patientId)
                .status(FormSubmission.SubmissionStatus.SUBMITTED)
                .fieldValues(storedValues)
                .submittedAt(LocalDateTime.now())
                .build();

        FormSubmission saved = submissionRepository.save(submission);
        log.info("Stored form submission {} ({} v{}) for owner {}/{}",
                saved.getId(), formType, schema.getVersion(), ownerType, ownerId);

        // File a PDF copy under the submitter's File Management ("My Files").
        // Pass the plaintext values so the PDF service can mask sensitive fields
        // (the persisted submission only holds ciphertext).
        fileSubmissionCopy(schema, saved, values);

        return new SubmissionResult(saved, List.of());
    }

    /** Return a copy of {@code values} with sensitive keys encrypted at rest. */
    private Map<String, Object> encryptSensitive(Map<String, Object> values, Set<String> sensitiveKeys) {
        Map<String, Object> out = new LinkedHashMap<>(values);
        for (String key : sensitiveKeys) {
            Object v = out.get(key);
            if (v != null && !(v instanceof String s && s.isBlank())) {
                out.put(key, tokenCryptor.encrypt(String.valueOf(v)));
            }
        }
        return out;
    }

    /**
     * Generate a PDF copy of the submission and store it as a {@code UserFile}
     * owned by the submitter, then link it back via {@code userFileId}. Best
     * effort: a failure here is logged but does not discard the saved data.
     */
    private void fileSubmissionCopy(FormSchema schema, FormSubmission submission, Map<String, Object> plaintextValues) {
        try {
            byte[] pdf = pdfService.generate(schema, submission, plaintextValues);
            String category = schema.getFileAttachment() != null
                    && schema.getFileAttachment().getCategory() != null
                    ? schema.getFileAttachment().getCategory()
                    : "ONBOARDING_FORM";
            String filename = submission.getFormType()
                    + "_v" + schema.getVersion()
                    + "_submission_" + submission.getId() + ".pdf";
            String description = schema.getTitle() + " (v" + schema.getVersion() + ") — submitted copy";

            com.careconnect.model.UserFile file = fileManagementService.storeGeneratedDocument(
                    pdf, filename, "application/pdf",
                    submission.getOwnerId(), submission.getOwnerType(),
                    category, description, submission.getPatientId());

            submission.setUserFileId(file.getId());
            submissionRepository.save(submission);
            log.info("Filed PDF copy (UserFile {}) for submission {}", file.getId(), submission.getId());
        } catch (Exception e) {
            log.error("Could not file PDF copy for submission {}: {}",
                    submission.getId(), e.getMessage(), e);
        }
    }

    /** Submissions owned by a given subject, most recent first. */
    @Transactional(readOnly = true)
    public List<FormSubmission> listForOwner(Long ownerId, UserFile.OwnerType ownerType) {
        List<FormSubmission> list = submissionRepository.findByOwnerIdAndOwnerType(ownerId, ownerType);
        list.sort((a, b) -> {
            LocalDateTime ta = a.getCreatedAt();
            LocalDateTime tb = b.getCreatedAt();
            if (ta == null || tb == null) return 0;
            return tb.compareTo(ta);
        });
        return list;
    }

    /**
     * Resolve the persisted {@link FormDefinition} row for the FK on a
     * submission. Falls back to a one-off sync of the bundled definitions if the
     * row is not present yet (e.g., before the startup initializer has run).
     */
    private FormDefinition resolveDefinition(FormSchema schema) {
        Optional<FormDefinition> found =
                definitionRepository.findByFormTypeAndVersion(schema.getFormType(), schema.getVersion());
        if (found.isPresent()) {
            return found.get();
        }
        log.info("Form definition {} v{} not registered yet; syncing bundled definitions",
                schema.getFormType(), schema.getVersion());
        schemaService.syncBundledDefinitions();
        return definitionRepository.findByFormTypeAndVersion(schema.getFormType(), schema.getVersion())
                .or(() -> definitionRepository.findFirstByFormTypeAndStatus(
                        schema.getFormType(), FormDefinition.FormStatus.ACTIVE))
                .orElseThrow(() -> new IllegalStateException(
                        "No form definition registered for " + schema.getFormType()));
    }
}

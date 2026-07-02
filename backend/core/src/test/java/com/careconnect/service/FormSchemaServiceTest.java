package com.careconnect.service;

import com.careconnect.model.UserFile;
import com.careconnect.model.forms.FieldType;
import com.careconnect.model.forms.FormField;
import com.careconnect.model.forms.FormSchema;
import com.careconnect.model.forms.FormSection;
import com.careconnect.model.forms.FormType;
import com.careconnect.model.forms.SourceDocumentMapping;
import com.careconnect.model.forms.ValidationRule;
import com.careconnect.model.forms.ValidationRuleType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Verifies the bundled hiring/onboarding form definitions and the
 * {@link FormSchemaService} parse/validation engine against the feature's
 * acceptance criteria:
 *
 * <ol>
 *   <li>The schema supports form-specific sections, fields, required status,
 *       and validation rules.</li>
 *   <li>Each form definition includes version and effective-date metadata.</li>
 *   <li>Each source document is mapped to its corresponding structured fields.</li>
 *   <li>The schema integrates with existing file-attachment records
 *       ({@link UserFile.FileCategory}).</li>
 * </ol>
 *
 * Pure unit test: uses a Jackson {@link ObjectMapper} configured like Spring
 * Boot's and exercises {@link FormSchemaService} without a Spring context or
 * database (the repository is unused by the methods under test).
 */
class FormSchemaServiceTest {

    private final ObjectMapper objectMapper =
            JsonMapper.builder().addModule(new JavaTimeModule()).build();

    private final FormSchemaService service = new FormSchemaService(null, objectMapper);

    /** All seven required hiring/onboarding documents must be bundled. */
    @Test
    void loadsAllSevenBundledDefinitions() {
        List<FormSchema> schemas = service.loadBundledSchemas();

        assertThat(schemas).hasSize(7);

        Set<FormType> covered = schemas.stream()
                .map(FormSchema::getFormType)
                .collect(Collectors.toSet());
        // Completeness: W-4, I-9, direct-deposit, sworn disclosure, health,
        // general hiring, and pre-hire are each represented exactly once.
        assertThat(covered).isEqualTo(EnumSet.allOf(FormType.class));
        assertThat(schemas.stream().map(FormSchema::getFormType).distinct().count())
                .isEqualTo(7L);
    }

    /** AC1-AC4 verified for every bundled definition. */
    @Test
    void everyDefinitionMeetsAcceptanceCriteria() {
        for (FormSchema schema : service.loadBundledSchemas()) {
            String where = "form " + schema.getFormType();

            // AC2: version + effective-date metadata.
            assertThat(schema.getVersion())
                    .as("%s: version metadata", where)
                    .isNotBlank();
            assertThat(schema.getEffectiveDate())
                    .as("%s: effective-date metadata", where)
                    .isNotNull();
            assertThat(schema.getTitle()).as("%s: title", where).isNotBlank();

            // AC3: source document is identified...
            assertThat(schema.getSourceDocument())
                    .as("%s: source document", where)
                    .isNotNull();
            assertThat(schema.getSourceDocument().getName())
                    .as("%s: source document name", where)
                    .isNotBlank();

            // AC4: integrates with existing UserFile file-attachment records.
            assertThat(schema.getFileAttachment())
                    .as("%s: file-attachment spec", where)
                    .isNotNull();
            String category = schema.getFileAttachment().getCategory();
            assertThat(isUserFileCategory(category))
                    .as("%s: fileAttachment.category '%s' must be a UserFile.FileCategory",
                            where, category)
                    .isTrue();

            // AC1: form-specific sections + fields.
            assertThat(schema.getSections())
                    .as("%s: sections", where)
                    .isNotNull()
                    .isNotEmpty();

            boolean anyValidationRule = false;
            boolean anySourceMapping = false;
            int fieldCount = 0;

            for (FormSection section : schema.getSections()) {
                assertThat(section.getId()).as("%s: section id", where).isNotBlank();
                assertThat(section.getTitle()).as("%s: section title", where).isNotBlank();
                assertThat(section.getFields())
                        .as("%s: section '%s' fields", where, section.getId())
                        .isNotNull()
                        .isNotEmpty();

                for (FormField field : section.getFields()) {
                    fieldCount++;
                    assertThat(field.getId())
                            .as("%s: field id in section %s", where, section.getId())
                            .isNotBlank();
                    assertThat(field.getFieldType())
                            .as("%s: field '%s' type", where, field.getId())
                            .isNotNull();
                    if (field.getValidations() != null && !field.getValidations().isEmpty()) {
                        anyValidationRule = true;
                    }
                    // AC3: at least some structured fields map back to the source document.
                    SourceDocumentMapping m = field.getSourceMapping();
                    if (m != null && m.getDocumentField() != null && !m.getDocumentField().isBlank()) {
                        anySourceMapping = true;
                    }
                }
            }

            assertThat(fieldCount).as("%s: total fields", where).isGreaterThan(0);
            // AC1: validation rules are present in the schema.
            assertThat(anyValidationRule)
                    .as("%s: at least one field declares validation rules", where)
                    .isTrue();
            // AC3: source-document-to-field mapping is present.
            assertThat(anySourceMapping)
                    .as("%s: at least one field maps to the source document", where)
                    .isTrue();
        }
    }

    /** A complete, valid W-4 submission passes validation with no errors. */
    @Test
    void validatesCompleteW4SubmissionWithoutErrors() {
        FormSchema w4 = w4Schema();

        List<String> errors = service.validateSubmission(w4, validW4Values());

        assertThat(errors).isEmpty();
    }

    /** Missing required fields and malformed values are reported. */
    @Test
    void reportsMissingRequiredAndInvalidValues() {
        FormSchema w4 = w4Schema();

        // Empty submission -> every required field flagged.
        List<String> missing = service.validateSubmission(w4, Map.of());
        assertThat(missing).isNotEmpty();
        assertThat(missing).anyMatch(e -> e.toLowerCase().contains("required"));

        // Valid submission with a malformed SSN and EIN -> format errors.
        Map<String, Object> values = validW4Values();
        values.put("step1_personal.ssn", "123");            // not a 9-digit SSN
        values.put("employer_only.employer_ein", "abc");    // not a valid EIN
        List<String> invalid = service.validateSubmission(w4, values);
        assertThat(invalid)
                .as("malformed SSN and EIN should both be reported")
                .hasSize(2);
    }

    /** DATE rule rejects a non-ISO value and accepts a valid one. */
    @Test
    void enforcesDateRule() {
        FormSchema schema = singleFieldSchema(FieldType.DATE,
                ValidationRule.builder().type(ValidationRuleType.DATE).build());

        assertThat(service.validateSubmission(schema, Map.of("s.f", "not-a-date"))).isNotEmpty();
        assertThat(service.validateSubmission(schema, Map.of("s.f", "2026-01-15"))).isEmpty();
    }

    /** AGE_MIN rule rejects a DOB below the threshold and accepts one above it. */
    @Test
    void enforcesAgeMinRule() {
        FormSchema schema = singleFieldSchema(FieldType.DATE,
                ValidationRule.builder().type(ValidationRuleType.AGE_MIN).value(18).build());

        assertThat(service.validateSubmission(schema,
                Map.of("s.f", LocalDate.now().minusYears(10).toString()))).isNotEmpty();
        assertThat(service.validateSubmission(schema,
                Map.of("s.f", LocalDate.now().minusYears(40).toString()))).isEmpty();
    }

    /** MIN/MAX reject non-numeric input (previously a silent no-op via NaN). */
    @Test
    void enforcesNumericMinMax() {
        FormSchema minSchema = singleFieldSchema(FieldType.NUMBER,
                ValidationRule.builder().type(ValidationRuleType.MIN).value(0).build());

        assertThat(service.validateSubmission(minSchema, Map.of("s.f", "abc"))).isNotEmpty();
        assertThat(service.validateSubmission(minSchema, Map.of("s.f", -1))).isNotEmpty();
        assertThat(service.validateSubmission(minSchema, Map.of("s.f", 5))).isEmpty();
    }

    /** Unknown keys are stripped; sensitive fields are reported. */
    @Test
    void stripsUnknownKeysAndReportsSensitive() {
        FormField ssn = FormField.builder()
                .id("ssn").label("SSN").fieldType(FieldType.SSN).required(false).order(0)
                .sensitive(true).build();
        FormSection section = FormSection.builder()
                .id("sec").title("Sec").order(0).fields(List.of(ssn)).build();
        FormSchema schema = FormSchema.builder()
                .formType(FormType.W4).title("t").version("1").sections(List.of(section)).build();

        Map<String, Object> in = new HashMap<>();
        in.put("sec.ssn", "123-45-6789");
        in.put("injected_field", "<script>");

        assertThat(service.retainKnownKeys(schema, in)).containsOnlyKeys("sec.ssn");
        assertThat(service.sensitiveKeys(schema)).containsExactly("sec.ssn");
    }

    // --- helpers ------------------------------------------------------------

    /** A minimal schema with a single optional field carrying one validation rule. */
    private FormSchema singleFieldSchema(FieldType type, ValidationRule rule) {
        FormField field = FormField.builder()
                .id("f").label("Field").fieldType(type).required(false).order(0)
                .validations(List.of(rule)).build();
        FormSection section = FormSection.builder()
                .id("s").title("S").order(0).fields(List.of(field)).build();
        return FormSchema.builder()
                .formType(FormType.W4).title("t").version("1").sections(List.of(section)).build();
    }

    private FormSchema w4Schema() {
        return service.loadBundledSchemas().stream()
                .filter(s -> s.getFormType() == FormType.W4)
                .findFirst()
                .orElseThrow(() -> new AssertionError("W-4 definition not bundled"));
    }

    /** Values keyed by "sectionId.fieldId" covering every required W-4 field. */
    private Map<String, Object> validW4Values() {
        Map<String, Object> v = new HashMap<>();
        v.put("step1_personal.first_name_mi", "Jane Q");
        v.put("step1_personal.last_name", "Doe");
        v.put("step1_personal.address", "123 Main St");
        v.put("step1_personal.city_state_zip", "Falls Church, VA 22041");
        v.put("step1_personal.ssn", "123-45-6789");
        v.put("step1_personal.filing_status", "SINGLE_OR_MFS");
        v.put("step5_signature.employee_signature", "Jane Q Doe");
        v.put("step5_signature.signature_date", "2026-01-15");
        v.put("employer_only.employer_name_address", "CareConnect, Falls Church VA");
        v.put("employer_only.first_date_employment", "2026-01-20");
        v.put("employer_only.employer_ein", "12-3456789");
        return new HashMap<>(v);
    }

    private boolean isUserFileCategory(String category) {
        if (category == null) {
            return false;
        }
        List<String> names = new ArrayList<>();
        for (UserFile.FileCategory c : UserFile.FileCategory.values()) {
            names.add(c.name());
        }
        return names.contains(category);
    }
}

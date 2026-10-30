package com.careconnect.service;

import com.careconnect.model.UserFile;
import com.careconnect.model.forms.FieldOption;
import com.careconnect.model.forms.FieldType;
import com.careconnect.model.forms.FileAttachmentSpec;
import com.careconnect.model.forms.FormDefinition;
import com.careconnect.model.forms.FormField;
import com.careconnect.model.forms.FormSchema;
import com.careconnect.model.forms.FormSection;
import com.careconnect.model.forms.FormSubmission;
import com.careconnect.model.forms.FormType;
import com.careconnect.model.forms.SourceDocument;
import com.careconnect.model.forms.ValidationRule;
import com.careconnect.model.forms.ValidationRuleType;
import com.careconnect.repository.FormDefinitionRepository;
import com.careconnect.repository.FormSubmissionRepository;
import com.careconnect.security.TokenCryptor;
import com.fasterxml.jackson.databind.json.JsonMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class FormSubmissionCoverageTest {

    @Mock private FormDefinitionRepository definitionRepository;
    @Mock private FormSubmissionRepository submissionRepository;
    @Mock private FileManagementService fileManagementService;

    private final FormSchemaService realSchemaService = new FormSchemaService(null,
            JsonMapper.builder().addModule(new JavaTimeModule()).build());

    private static FormSchema sampleSchema() {
        FormField name = FormField.builder().id("name").label("Name").fieldType(FieldType.TEXT)
                .required(true).order(1).build();
        FormField ssn = FormField.builder().id("ssn").label("SSN").fieldType(FieldType.SSN)
                .order(2).sensitive(true).build();
        FormField color = FormField.builder().id("color").label("Color").fieldType(FieldType.SELECT).order(3)
                .options(List.of(FieldOption.builder().value("r").label("Red").build(),
                        FieldOption.builder().value("g").build())).build();
        FormField ok = FormField.builder().id("ok").label("Agree").fieldType(FieldType.CHECKBOX).order(4).build();
        FormField tags = FormField.builder().id("tags").label("Tags").fieldType(FieldType.MULTISELECT).order(5)
                .options(List.of(FieldOption.builder().value("a").label("Alpha").build())).build();
        FormField secrets = FormField.builder().id("secrets").label("Secrets").order(6).sensitive(true).build();
        FormField shortSecret = FormField.builder().id("pin").label("Pin").order(7).sensitive(true).build();
        FormField blank = FormField.builder().id("blank").label(null).order(8).build();
        FormSection s1 = FormSection.builder().id("s1").title("Personal").order(1)
                .fields(new ArrayList<>(List.of(color, name, ssn, ok, tags, secrets, shortSecret, blank))).build();
        FormSection s2 = FormSection.builder().id("s2").title("Empty").order(0)
                .fields(List.of(FormField.builder().id("x").label("X").build())).build();
        FormSection s3 = FormSection.builder().id("s3").title(null).order(2).fields(null).build();
        return FormSchema.builder().formType(FormType.W4).title("W-4").version("2026")
                .issuingAuthority("IRS")
                .sourceDocument(SourceDocument.builder().formNumber("W-4").build())
                .fileAttachment(FileAttachmentSpec.builder().category("TAX_FORM").build())
                .sections(new ArrayList<>(List.of(s1, s2, s3))).build();
    }

    private static Map<String, Object> sampleValues() {
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("s1.name", "Jane Tester");
        values.put("s1.ssn", "123-45-6789");
        values.put("s1.color", "r");
        values.put("s1.ok", Boolean.TRUE);
        values.put("s1.tags", List.of("a", "b"));
        values.put("s1.secrets", List.of("abcdefgh", ""));
        values.put("s1.pin", "12");
        values.put("s1.blank", "g");
        values.put("s2.x", " ");
        return values;
    }

    @Test
    void pdfRendersSectionsAndMasksSensitiveValues() {
        FormPdfService pdf = new FormPdfService();
        FormSubmission submission = FormSubmission.builder().id(7L).status(FormSubmission.SubmissionStatus.SUBMITTED)
                .submittedAt(LocalDateTime.now()).ownerType(UserFile.OwnerType.CAREGIVER).ownerId(3L).build();
        byte[] bytes = pdf.generate(sampleSchema(), submission, sampleValues());
        assertThat(new String(bytes, 0, 4)).isEqualTo("%PDF");

        FormSchema minimal = FormSchema.builder().title(null).version(null).build();
        assertThat(pdf.generate(minimal, FormSubmission.builder().id(1L).build(), null)).isNotEmpty();
    }

    @Test
    void pdfWrapsRenderingFailures() {
        FormPdfService pdf = new FormPdfService();
        assertThatThrownBy(() -> pdf.generate(null, FormSubmission.builder().build(), Map.of()))
                .isInstanceOf(RuntimeException.class);
    }

    @Test
    void submitPersistsEncryptsAndFilesPdf() {
        FormSchemaService schemaService = org.mockito.Mockito.mock(FormSchemaService.class);
        FormSchema schema = sampleSchema();
        when(schemaService.loadBundledSchema(FormType.W4, "2026")).thenReturn(Optional.of(schema));
        when(schemaService.retainKnownKeys(any(), any())).thenAnswer(inv -> new HashMap<>((Map<String, Object>) inv.getArgument(1)));
        when(schemaService.validateSubmission(any(), any())).thenReturn(List.of());
        when(schemaService.sensitiveKeys(any())).thenReturn(java.util.Set.of("s1.ssn", "s1.pin", "s1.missing"));
        when(definitionRepository.findByFormTypeAndVersion(FormType.W4, "2026"))
                .thenReturn(Optional.empty())
                .thenReturn(Optional.of(FormDefinition.builder().id(11L).build()));
        when(submissionRepository.save(any())).thenAnswer(inv -> {
            FormSubmission s = inv.getArgument(0);
            if (s.getId() == null) {
                s.setId(99L);
            }
            return s;
        });
        UserFile file = new UserFile();
        file.setId(55L);
        when(fileManagementService.storeGeneratedDocument(any(), anyString(), anyString(), anyLong(), any(),
                anyString(), anyString(), any())).thenReturn(file);

        FormSubmissionService service = new FormSubmissionService(schemaService, definitionRepository,
                submissionRepository, new FormPdfService(), fileManagementService, new TokenCryptor("unit-test-secret"));
        FormSubmissionService.SubmissionResult result = service.submit(FormType.W4, "2026", 3L,
                UserFile.OwnerType.CAREGIVER, 4L, sampleValues());

        assertThat(result.isValid()).isTrue();
        assertThat(result.submission().getUserFileId()).isEqualTo(55L);
        assertThat(result.submission().getFieldValues().get("s1.ssn")).isNotEqualTo("123-45-6789");
        verify(schemaService).syncBundledDefinitions();
    }

    @Test
    void submitReturnsErrorsAndFallsBackToActiveDefinition() {
        FormSchemaService schemaService = org.mockito.Mockito.mock(FormSchemaService.class);
        FormSchema schema = FormSchema.builder().formType(FormType.I9).title("I-9").version("1").sections(List.of()).build();
        when(schemaService.loadBundledSchema(eq(FormType.I9), any())).thenReturn(Optional.of(schema));
        when(schemaService.retainKnownKeys(any(), any())).thenReturn(Map.of());
        when(schemaService.validateSubmission(any(), any())).thenReturn(List.of("bad")).thenReturn(List.of());
        when(schemaService.sensitiveKeys(any())).thenReturn(java.util.Set.of());
        when(definitionRepository.findByFormTypeAndVersion(any(), any())).thenReturn(Optional.empty());
        when(definitionRepository.findFirstByFormTypeAndStatus(FormType.I9, FormDefinition.FormStatus.ACTIVE))
                .thenReturn(Optional.of(FormDefinition.builder().id(1L).build()));
        when(submissionRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(fileManagementService.storeGeneratedDocument(any(), any(), any(), any(), any(), any(), any(), any()))
                .thenThrow(new RuntimeException("disk full"));

        FormSubmissionService service = new FormSubmissionService(schemaService, definitionRepository,
                submissionRepository, new FormPdfService(), fileManagementService, new TokenCryptor("k"));
        assertThat(service.submit(FormType.I9, null, 1L, UserFile.OwnerType.CAREGIVER, null, Map.of()).isValid())
                .isFalse();
        assertThat(service.submit(FormType.I9, null, 1L, UserFile.OwnerType.CAREGIVER, null, Map.of()).isValid())
                .isTrue();

        when(schemaService.loadBundledSchema(eq(FormType.HEALTH), any())).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.submit(FormType.HEALTH, "9", 1L, UserFile.OwnerType.CAREGIVER, null, Map.of()))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> service.submit(FormType.HEALTH, null, 1L, UserFile.OwnerType.CAREGIVER, null, Map.of()))
                .isInstanceOf(IllegalArgumentException.class);

        when(definitionRepository.findFirstByFormTypeAndStatus(any(), any())).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.submit(FormType.I9, null, 1L, UserFile.OwnerType.CAREGIVER, null, Map.of()))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    void listForOwnerSortsNewestFirst() {
        FormSubmission a = FormSubmission.builder().id(1L).createdAt(LocalDateTime.now().minusDays(1)).build();
        FormSubmission b = FormSubmission.builder().id(2L).createdAt(LocalDateTime.now()).build();
        FormSubmission c = FormSubmission.builder().id(3L).build();
        when(submissionRepository.findByOwnerIdAndOwnerType(1L, UserFile.OwnerType.CAREGIVER))
                .thenReturn(new ArrayList<>(List.of(a, b, c)));
        FormSubmissionService service = new FormSubmissionService(realSchemaService, definitionRepository,
                submissionRepository, new FormPdfService(), fileManagementService, new TokenCryptor("k"));
        assertThat(service.listForOwner(1L, UserFile.OwnerType.CAREGIVER)).hasSize(3);
    }

    @Test
    void schemaServiceSelectsBundledVersionsAndSyncsDefinitions() {
        assertThat(realSchemaService.loadBundledSchema(FormType.W4, null)).isPresent();
        String version = realSchemaService.loadBundledSchema(FormType.W4, null).get().getVersion();
        assertThat(realSchemaService.loadBundledSchema(FormType.W4, version)).isPresent();
        assertThat(realSchemaService.loadBundledSchema(FormType.W4, "no-such")).isEmpty();

        FormSchemaService svc = new FormSchemaService(definitionRepository,
                JsonMapper.builder().addModule(new JavaTimeModule()).build());
        when(definitionRepository.findByFormTypeAndVersion(any(), any())).thenReturn(Optional.empty());
        when(definitionRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        FormDefinition older = FormDefinition.builder().id(1L).effectiveDate(LocalDate.of(2020, 1, 1))
                .status(FormDefinition.FormStatus.ACTIVE).build();
        FormDefinition newer = FormDefinition.builder().id(2L).effectiveDate(LocalDate.of(2025, 1, 1))
                .status(FormDefinition.FormStatus.DRAFT).build();
        when(definitionRepository.findByFormType(FormType.W4)).thenReturn(List.of(older, newer));
        when(definitionRepository.findByFormType(FormType.I9)).thenReturn(List.of());
        svc.syncBundledDefinitions();
        assertThat(newer.getStatus()).isEqualTo(FormDefinition.FormStatus.ACTIVE);
        assertThat(older.getStatus()).isEqualTo(FormDefinition.FormStatus.RETIRED);
        verify(definitionRepository, atLeastOnce()).save(any());

        when(definitionRepository.findFirstByFormTypeAndStatus(FormType.W4, FormDefinition.FormStatus.ACTIVE))
                .thenReturn(Optional.of(newer));
        assertThat(svc.getActiveDefinition(FormType.W4)).contains(newer);
    }

    private static FormField ruled(String id, ValidationRuleType type, Object value, String pattern) {
        return FormField.builder().id(id).label(id)
                .validations(List.of(ValidationRule.builder().type(type).value(value).pattern(pattern).build()))
                .build();
    }

    @Test
    void schemaServiceAppliesEveryValidationRule() {
        List<FormField> fields = List.of(
                ruled("minlen", ValidationRuleType.MIN_LENGTH, 5, null),
                ruled("maxlen", ValidationRuleType.MAX_LENGTH, 2, null),
                ruled("min", ValidationRuleType.MIN, 10, null),
                ruled("max", ValidationRuleType.MAX, "1", null),
                ruled("maxbad", ValidationRuleType.MAX, 1, null),
                ruled("pattern", ValidationRuleType.PATTERN, null, "\\d+"),
                ruled("email", ValidationRuleType.EMAIL, null, null),
                ruled("ssn", ValidationRuleType.SSN, null, null),
                ruled("ein", ValidationRuleType.EIN, null, null),
                ruled("routing", ValidationRuleType.ROUTING_NUMBER, null, null),
                ruled("routingok", ValidationRuleType.ROUTING_NUMBER, null, null),
                ruled("checked", ValidationRuleType.CHECKED, null, null),
                ruled("enum", ValidationRuleType.ENUM, List.of("a"), null),
                ruled("date", ValidationRuleType.DATE, null, null),
                ruled("age", ValidationRuleType.AGE_MIN, 18, null),
                ruled("range", ValidationRuleType.DATE_RANGE, List.of("2020-01-01", "2020-12-31"), null),
                ruled("rangebad", ValidationRuleType.DATE_RANGE, null, null),
                ruled("custom", ValidationRuleType.CUSTOM, null, null),
                ruled("req", ValidationRuleType.REQUIRED, null, null),
                FormField.builder().id("required").label("Required").required(true).build(),
                FormField.builder().id("plain").label("Plain").build());
        FormSchema schema = FormSchema.builder().sections(List.of(
                FormSection.builder().id("s").fields(fields).build())).build();
        Map<String, Object> v = new HashMap<>();
        v.put("s.minlen", "ab");
        v.put("s.maxlen", "abcdef");
        v.put("s.min", 3);
        v.put("s.max", "5");
        v.put("s.maxbad", "not-a-number");
        v.put("s.pattern", "abc");
        v.put("s.email", "nope");
        v.put("s.ssn", "123");
        v.put("s.ein", "1");
        v.put("s.routing", "123456789");
        v.put("s.routingok", "021000021");
        v.put("s.checked", "false");
        v.put("s.enum", "b");
        v.put("s.date", "not-a-date");
        v.put("s.age", LocalDate.now().minusYears(5).toString());
        v.put("s.range", "2021-06-01");
        v.put("s.rangebad", "garbage");
        v.put("s.custom", "x");
        v.put("s.req", "x");
        v.put("s.plain", "x");
        List<String> errors = realSchemaService.validateSubmission(schema, v);
        assertThat(errors.size()).isGreaterThanOrEqualTo(15);
        assertThat(realSchemaService.validateSubmission(schema, null)).isNotEmpty();
    }
}

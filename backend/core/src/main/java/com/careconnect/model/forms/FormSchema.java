package com.careconnect.model.forms;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import com.fasterxml.jackson.datatype.jsr310.deser.LocalDateDeserializer;
import com.fasterxml.jackson.datatype.jsr310.ser.LocalDateSerializer;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.util.List;

/**
 * In-memory, Jackson-mapped representation of one JSON form definition
 * (e.g., {@code forms/w4-2026.form.json}). This is the object graph that
 * {@link FormDefinition} stores as JSONB and that the API serves to the
 * Flutter client to render and validate a form.
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonIgnoreProperties(ignoreUnknown = true)
public class FormSchema {
    private FormType formType;
    private String title;
    private String description;
    private String issuingAuthority;

    /** Definition version (official form edition where one exists). */
    private String version;

    @JsonSerialize(using = LocalDateSerializer.class)
    @JsonDeserialize(using = LocalDateDeserializer.class)
    private LocalDate effectiveDate;

    @JsonSerialize(using = LocalDateSerializer.class)
    @JsonDeserialize(using = LocalDateDeserializer.class)
    private LocalDate expirationDate;

    private SourceDocument sourceDocument;
    private FileAttachmentSpec fileAttachment;
    private List<FormSection> sections;
}

package com.careconnect.service;

import com.careconnect.model.forms.FieldOption;
import com.careconnect.model.forms.FormField;
import com.careconnect.model.forms.FormSchema;
import com.careconnect.model.forms.FormSection;
import com.careconnect.model.forms.FormSubmission;
import com.lowagie.text.Chunk;
import com.lowagie.text.Document;
import com.lowagie.text.Font;
import com.lowagie.text.FontFactory;
import com.lowagie.text.PageSize;
import com.lowagie.text.Paragraph;
import com.lowagie.text.pdf.PdfWriter;
import org.springframework.stereotype.Service;

import java.awt.Color;
import java.io.ByteArrayOutputStream;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * Renders a completed {@link FormSubmission} as a human-readable PDF copy,
 * mirroring the form's sections and the values the user submitted. The PDF is
 * filed as a {@code UserFile} so it appears under the user's File Management.
 */
@Service
public class FormPdfService {

    private static final DateTimeFormatter TS =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    /**
     * Build a PDF document for the submitted form.
     *
     * @param plaintextValues the submitted values in clear text (the persisted
     *     submission only holds ciphertext for sensitive fields); sensitive
     *     fields are masked in the rendered PDF.
     */
    public byte[] generate(FormSchema schema, FormSubmission submission, Map<String, Object> plaintextValues) {
        Map<String, Object> values = plaintextValues == null ? Map.of() : plaintextValues;

        Font titleFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 16, new Color(33, 33, 33));
        Font metaFont = FontFactory.getFont(FontFactory.HELVETICA, 9, new Color(110, 110, 110));
        Font sectionFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 12, new Color(20, 20, 20));
        Font labelFont = FontFactory.getFont(FontFactory.HELVETICA_BOLD, 10, new Color(60, 60, 60));
        Font valueFont = FontFactory.getFont(FontFactory.HELVETICA, 10, Color.BLACK);
        Font footerFont = FontFactory.getFont(FontFactory.HELVETICA_OBLIQUE, 8, new Color(150, 150, 150));

        Document document = new Document(PageSize.LETTER, 54, 54, 54, 54);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        try {
            PdfWriter.getInstance(document, baos);
            document.open();

            document.add(new Paragraph(safe(schema.getTitle()), titleFont));

            StringBuilder meta = new StringBuilder();
            if (schema.getSourceDocument() != null
                    && schema.getSourceDocument().getFormNumber() != null) {
                meta.append("Form ").append(schema.getSourceDocument().getFormNumber()).append("  •  ");
            }
            meta.append("Version ").append(safe(schema.getVersion()));
            if (schema.getIssuingAuthority() != null) {
                meta.append("  •  ").append(schema.getIssuingAuthority());
            }
            Paragraph metaP = new Paragraph(meta.toString(), metaFont);
            metaP.setSpacingAfter(2f);
            document.add(metaP);

            Paragraph subP = new Paragraph(
                    "Submission #" + submission.getId()
                            + "  •  Status: " + submission.getStatus()
                            + (submission.getSubmittedAt() != null
                                    ? "  •  Submitted: " + submission.getSubmittedAt().format(TS)
                                    : "")
                            + "  •  Filed by: " + submission.getOwnerType() + " #" + submission.getOwnerId(),
                    metaFont);
            subP.setSpacingAfter(10f);
            document.add(subP);

            List<FormSection> sections = new ArrayList<>(
                    schema.getSections() == null ? List.of() : schema.getSections());
            sections.sort(Comparator.comparingInt(FormSection::getOrder));

            for (FormSection section : sections) {
                List<FormField> fields = new ArrayList<>(
                        section.getFields() == null ? List.of() : section.getFields());
                fields.sort(Comparator.comparingInt(FormField::getOrder));

                // Only render sections that have at least one captured value.
                List<FormField> answered = new ArrayList<>();
                for (FormField f : fields) {
                    Object v = values.get(section.getId() + "." + f.getId());
                    if (!isBlank(v)) {
                        answered.add(f);
                    }
                }
                if (answered.isEmpty()) {
                    continue;
                }

                Paragraph sectionP = new Paragraph(safe(section.getTitle()), sectionFont);
                sectionP.setSpacingBefore(12f);
                sectionP.setSpacingAfter(4f);
                document.add(sectionP);

                for (FormField f : answered) {
                    Object v = values.get(section.getId() + "." + f.getId());
                    Paragraph line = new Paragraph();
                    line.add(new Chunk(safe(f.getLabel()) + ": ", labelFont));
                    line.add(new Chunk(displayValue(f, v), valueFont));
                    line.setSpacingAfter(3f);
                    document.add(line);
                }
            }

            Paragraph footer = new Paragraph(
                    "This document is a copy of the information submitted through CareConnect.",
                    footerFont);
            footer.setSpacingBefore(18f);
            document.add(footer);

            document.close();
            return baos.toByteArray();
        } catch (Exception e) {
            if (document.isOpen()) {
                document.close();
            }
            throw new RuntimeException("Failed to generate form PDF: " + e.getMessage(), e);
        }
    }

    private String displayValue(FormField field, Object v) {
        if (v == null) {
            return "";
        }
        if (v instanceof Boolean b) {
            return b ? "Yes" : "No";
        }
        if (v instanceof List<?> list) {
            List<String> labels = new ArrayList<>();
            for (Object item : list) {
                labels.add(field.isSensitive() ? mask(String.valueOf(item)) : optionLabel(field, item));
            }
            return String.join(", ", labels);
        }
        // Honor the field's sensitive flag: never render full PII/PHI in the PDF.
        if (field.isSensitive()) {
            return mask(String.valueOf(v));
        }
        return optionLabel(field, v);
    }

    /** Mask a sensitive value, revealing only the last 4 characters (e.g. ***-**-1234). */
    private String mask(String s) {
        if (s == null || s.isEmpty()) {
            return "";
        }
        String digits = s.replaceAll("\\s", "");
        if (digits.length() <= 4) {
            return "****";
        }
        return "****" + digits.substring(digits.length() - 4);
    }

    private String optionLabel(FormField field, Object v) {
        String s = String.valueOf(v);
        if (field.getOptions() != null) {
            for (FieldOption o : field.getOptions()) {
                if (o.getValue() != null && o.getValue().equals(s)) {
                    return o.getLabel() != null ? o.getLabel() : s;
                }
            }
        }
        return s;
    }

    private boolean isBlank(Object v) {
        return v == null || (v instanceof String s && s.isBlank());
    }

    private String safe(String s) {
        return s == null ? "" : s;
    }
}

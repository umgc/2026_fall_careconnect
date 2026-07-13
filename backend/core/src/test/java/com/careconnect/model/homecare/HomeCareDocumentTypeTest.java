package com.careconnect.model.homecare;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Schema safety for home-care document types: every type carries a
 * well-formed, non-empty field schema that the extraction pipeline can
 * enforce.
 */
class HomeCareDocumentTypeTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void everyType_hasDisplayNameAndNonEmptySchema() {
        for (HomeCareDocumentType type : HomeCareDocumentType.values()) {
            assertThat(type.getDisplayName()).isNotBlank();
            assertThat(type.getFieldSchema()).isNotEmpty();
            type.getFieldSchema().forEach((key, label) -> {
                assertThat(key).isNotBlank();
                assertThat(label).isNotBlank();
            });
        }
    }

    @Test
    void promptSchemaJson_isValidJsonWithExactlyTheAllowedFields() throws Exception {
        for (HomeCareDocumentType type : HomeCareDocumentType.values()) {
            JsonNode node = objectMapper.readTree(type.promptSchemaJson());

            assertThat(node.isObject()).isTrue();

            List<String> jsonKeys = new ArrayList<>();
            node.fieldNames().forEachRemaining(jsonKeys::add);

            assertThat(jsonKeys)
                    .containsExactlyElementsOf(type.getFieldSchema().keySet());
        }
    }

    @Test
    void schemasDiffer_betweenDocumentTypes() {
        // The employment application schema must not leak into other types.
        assertThat(HomeCareDocumentType.CERTIFICATION.getFieldSchema())
                .doesNotContainKey("positionAppliedFor");
        assertThat(HomeCareDocumentType.TAX_FORM.getFieldSchema())
                .doesNotContainKey("certificationNumber");
        assertThat(HomeCareDocumentType.EMPLOYMENT_APPLICATION.getFieldSchema())
                .containsKey("positionAppliedFor");
    }

    @Test
    void fieldSchema_isUnmodifiable() {
        assertThatThrownBy(() ->
                HomeCareDocumentType.EMPLOYMENT_APPLICATION.getFieldSchema().put("hacked", "Hacked"))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void fromString_parsesKnownTypesCaseInsensitively() {
        assertThat(HomeCareDocumentType.fromString("EMPLOYMENT_APPLICATION"))
                .contains(HomeCareDocumentType.EMPLOYMENT_APPLICATION);
        assertThat(HomeCareDocumentType.fromString("certification"))
                .contains(HomeCareDocumentType.CERTIFICATION);
        assertThat(HomeCareDocumentType.fromString("  tax_form  "))
                .contains(HomeCareDocumentType.TAX_FORM);
    }

    @Test
    void fromString_returnsEmptyForUnknownOrBlank() {
        assertThat(HomeCareDocumentType.fromString("INVOICE")).isEmpty();
        assertThat(HomeCareDocumentType.fromString("")).isEmpty();
        assertThat(HomeCareDocumentType.fromString("   ")).isEmpty();
        assertThat(HomeCareDocumentType.fromString(null)).isEmpty();
    }

    @Test
    void fromString_neverThrows() {
        Optional<HomeCareDocumentType> result =
                HomeCareDocumentType.fromString("definitely-not-a-type!!");
        assertThat(result).isEmpty();
    }
}

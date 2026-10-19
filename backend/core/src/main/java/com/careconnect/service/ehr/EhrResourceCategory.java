package com.careconnect.service.ehr;

import java.util.Map;

/**
 * Maps a FHIR {@code resourceType} to the UI "Record Type" category the Unified Health Data screen
 * filters on. Source of truth: Cononical_0_Epic-Unified-Health-Data-Integration_v1_2 §5.1.
 *
 * <p>Source-agnostic: the categories describe clinical concepts, not Epic specifically, so the same
 * mapping serves Medicare/other connectors as they land. Unknown types fall back to {@code Other}.
 */
public final class EhrResourceCategory {

    private EhrResourceCategory() {
    }

    public static final String OTHER = "Other";

    private static final Map<String, String> BY_RESOURCE_TYPE = Map.ofEntries(
            Map.entry("Condition", "Conditions"),
            Map.entry("MedicationRequest", "Medications"),
            Map.entry("MedicationStatement", "Medications"),
            Map.entry("AllergyIntolerance", "Allergies"),
            Map.entry("Observation", "Results"),
            Map.entry("DiagnosticReport", "Results"),
            Map.entry("Immunization", "Immunizations"),
            Map.entry("Procedure", "Procedures"),
            Map.entry("Encounter", "Care Context"),
            Map.entry("CarePlan", "Care Context"),
            Map.entry("Goal", "Care Context"),
            Map.entry("CareTeam", "Care Context"),
            Map.entry("FamilyMemberHistory", "Care Context"),
            Map.entry("Device", "Care Context"),
            Map.entry("Coverage", "Coverage/Insurance"),
            Map.entry("DocumentReference", "Documents"));

    /** The UI category for a FHIR resource type, or {@code Other} when unmapped/null. */
    public static String categoryFor(final String resourceType) {
        if (resourceType == null) {
            return OTHER;
        }
        return BY_RESOURCE_TYPE.getOrDefault(resourceType, OTHER);
    }
}

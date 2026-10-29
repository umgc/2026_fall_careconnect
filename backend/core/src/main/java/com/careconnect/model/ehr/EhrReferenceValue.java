package com.careconnect.model.ehr;

/** A FHIR reference and its source-provided display value. */
public record EhrReferenceValue(String reference, String display) {}

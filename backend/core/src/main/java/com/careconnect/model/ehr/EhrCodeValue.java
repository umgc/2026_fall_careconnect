package com.careconnect.model.ehr;

/**
 * One source coding retained inside a normalized EHR record.
 *
 * <p>The coding system and code remain authoritative. Display and concept text are retained for
 * presentation, but must never be used as record identity.
 */
public record EhrCodeValue(String system, String code, String display, String text) {}

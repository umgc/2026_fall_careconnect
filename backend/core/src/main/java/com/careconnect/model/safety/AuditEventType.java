package com.careconnect.model.safety;

/** WBS 3.15.6
 *  (eventType) event categories captured in the AI audit ledger */
public enum AuditEventType {
    /** An AI query was submitted by a user */
    QUERY,
    /** A response was returned to the user from an AI feature */
    RESPONSE,
    /** A secondary validation pass ran on AI output before delivery */
    VALIDATION,
    /** A user explicitly confirmed or dismissed an AI-generated action */
    CONFIRMATION
}

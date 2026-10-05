package com.careconnect.model;

/**
 * Independently fenced durable progress markers for call termination.
 */
public enum TerminationStep {
    SENTIMENT,
    SUMMARY,
    RECORDING,
    MEETING,
    COMPLETE
}

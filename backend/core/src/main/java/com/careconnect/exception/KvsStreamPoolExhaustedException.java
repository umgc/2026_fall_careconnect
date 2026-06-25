package com.careconnect.exception;

/** Thrown when no pre-provisioned KVS streams remain available in the pool. */
public class KvsStreamPoolExhaustedException extends RuntimeException {

    public KvsStreamPoolExhaustedException(final String message) {
        super(message);
    }
}

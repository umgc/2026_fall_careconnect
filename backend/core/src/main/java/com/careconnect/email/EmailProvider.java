package com.careconnect.email;

import com.careconnect.model.EmailCredential;

/**
 * Provider-agnostic mail connection surface used by USPS Informed Delivery.
 */
public interface EmailProvider {

    EmailCredential.Provider provider();

    AuthMode authMode();

    /** Relative OAuth start path (null for IMAP-only providers). */
    String reconnectPath();

    enum AuthMode {
        OAUTH,
        IMAP
    }
}

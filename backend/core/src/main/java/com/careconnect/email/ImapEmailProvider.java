package com.careconnect.email;

import com.careconnect.model.EmailCredential;
import org.springframework.stereotype.Component;

@Component
public class ImapEmailProvider implements EmailProvider {
    @Override
    public EmailCredential.Provider provider() {
        return EmailCredential.Provider.IMAP;
    }

    @Override
    public AuthMode authMode() {
        return AuthMode.IMAP;
    }

    @Override
    public String reconnectPath() {
        return "/v1/api/email-credentials/imap/connect";
    }
}

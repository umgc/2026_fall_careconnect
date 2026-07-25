package com.careconnect.email;

import com.careconnect.model.EmailCredential;
import org.springframework.stereotype.Component;

@Component
public class MicrosoftEmailProvider implements EmailProvider {
    @Override
    public EmailCredential.Provider provider() {
        return EmailCredential.Provider.OUTLOOK;
    }

    @Override
    public AuthMode authMode() {
        return AuthMode.OAUTH;
    }

    @Override
    public String reconnectPath() {
        return "/oauth/microsoft/start";
    }
}

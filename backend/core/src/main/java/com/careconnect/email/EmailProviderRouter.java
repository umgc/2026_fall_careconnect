package com.careconnect.email;

import com.careconnect.model.EmailCredential;
import org.springframework.stereotype.Component;

import java.util.EnumMap;
import java.util.List;
import java.util.Map;

@Component
public class EmailProviderRouter {

    private final Map<EmailCredential.Provider, EmailProvider> byProvider;
    private final EmailDomainDetector domainDetector;

    public EmailProviderRouter(final List<EmailProvider> providers, final EmailDomainDetector domainDetector) {
        this.domainDetector = domainDetector;
        this.byProvider = new EnumMap<>(EmailCredential.Provider.class);
        for (final EmailProvider provider : providers) {
            byProvider.put(provider.provider(), provider);
        }
    }

    public EmailProvider resolve(final EmailCredential.Provider provider) {
        final EmailProvider found = byProvider.get(provider);
        if (found != null) {
            return found;
        }
        return byProvider.get(EmailCredential.Provider.IMAP);
    }

    public EmailProvider resolveForEmail(final String email) {
        return resolve(domainDetector.detectProvider(email));
    }

    public EmailDomainDetector domains() {
        return domainDetector;
    }
}

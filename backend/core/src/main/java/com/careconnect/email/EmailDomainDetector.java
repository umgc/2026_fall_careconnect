package com.careconnect.email;

import com.careconnect.model.EmailCredential;
import org.springframework.stereotype.Component;

import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Detects mail provider from an email domain and routes to OAuth or IMAP.
 * Unknown / custom business domains always map to IMAP.
 */
@Component
public class EmailDomainDetector {

    private static final Map<String, EmailCredential.Provider> DOMAIN_MAP = Map.ofEntries(
            Map.entry("gmail.com", EmailCredential.Provider.GMAIL),
            Map.entry("googlemail.com", EmailCredential.Provider.GMAIL),
            Map.entry("outlook.com", EmailCredential.Provider.OUTLOOK),
            Map.entry("hotmail.com", EmailCredential.Provider.OUTLOOK),
            Map.entry("live.com", EmailCredential.Provider.OUTLOOK),
            Map.entry("msn.com", EmailCredential.Provider.OUTLOOK),
            Map.entry("yahoo.com", EmailCredential.Provider.YAHOO),
            Map.entry("ymail.com", EmailCredential.Provider.YAHOO),
            Map.entry("icloud.com", EmailCredential.Provider.APPLE),
            Map.entry("me.com", EmailCredential.Provider.APPLE),
            Map.entry("mac.com", EmailCredential.Provider.APPLE),
            Map.entry("aol.com", EmailCredential.Provider.AOL),
            Map.entry("zoho.com", EmailCredential.Provider.ZOHO),
            Map.entry("zohomail.com", EmailCredential.Provider.ZOHO),
            Map.entry("proton.me", EmailCredential.Provider.IMAP),
            Map.entry("protonmail.com", EmailCredential.Provider.IMAP),
            Map.entry("tutamail.com", EmailCredential.Provider.IMAP),
            Map.entry("fastmail.com", EmailCredential.Provider.IMAP),
            Map.entry("gmx.com", EmailCredential.Provider.IMAP),
            Map.entry("gmx.net", EmailCredential.Provider.IMAP),
            Map.entry("mail.com", EmailCredential.Provider.IMAP),
            Map.entry("yandex.com", EmailCredential.Provider.IMAP),
            Map.entry("yandex.ru", EmailCredential.Provider.IMAP),
            Map.entry("qq.com", EmailCredential.Provider.IMAP),
            Map.entry("163.com", EmailCredential.Provider.IMAP),
            Map.entry("126.com", EmailCredential.Provider.IMAP),
            Map.entry("naver.com", EmailCredential.Provider.IMAP),
            Map.entry("hanmail.net", EmailCredential.Provider.IMAP),
            Map.entry("rediffmail.com", EmailCredential.Provider.IMAP),
            Map.entry("web.de", EmailCredential.Provider.IMAP),
            Map.entry("freenet.de", EmailCredential.Provider.IMAP)
    );

    /** Domains that support native OAuth in this codebase (Google + Microsoft). */
    private static final Set<EmailCredential.Provider> NATIVE_OAUTH = Set.of(
            EmailCredential.Provider.GMAIL,
            EmailCredential.Provider.OUTLOOK
    );

    public Optional<String> extractDomain(final String email) {
        if (email == null) {
            return Optional.empty();
        }
        final String trimmed = email.trim().toLowerCase(Locale.ROOT);
        final int at = trimmed.lastIndexOf('@');
        if (at <= 0 || at == trimmed.length() - 1) {
            return Optional.empty();
        }
        return Optional.of(trimmed.substring(at + 1));
    }

    public EmailCredential.Provider detectProvider(final String email) {
        return extractDomain(email)
                .map(domain -> DOMAIN_MAP.getOrDefault(domain, EmailCredential.Provider.IMAP))
                .orElse(EmailCredential.Provider.IMAP);
    }

    public EmailProvider.AuthMode authModeFor(final EmailCredential.Provider provider) {
        return NATIVE_OAUTH.contains(provider) ? EmailProvider.AuthMode.OAUTH : EmailProvider.AuthMode.IMAP;
    }

    public String reconnectPathFor(final EmailCredential.Provider provider) {
        return switch (provider) {
            case GMAIL -> "/oauth/google/start";
            case OUTLOOK -> "/oauth/microsoft/start";
            default -> "/v1/api/email-credentials/imap/connect";
        };
    }

    public String defaultImapHost(final EmailCredential.Provider provider, final String email) {
        final String domain = extractDomain(email).orElse("localhost");
        return switch (provider) {
            case YAHOO -> "imap.mail.yahoo.com";
            case APPLE -> "imap.mail.me.com";
            case AOL -> "imap.aol.com";
            case ZOHO -> "imap.zoho.com";
            case GMAIL -> "imap.gmail.com";
            case OUTLOOK -> "outlook.office365.com";
            default -> "imap." + domain;
        };
    }
}

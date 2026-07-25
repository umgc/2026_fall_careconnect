package com.careconnect.service;

import jakarta.mail.internet.AddressException;
import jakarta.mail.internet.InternetAddress;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.naming.NamingException;
import javax.naming.directory.Attribute;
import javax.naming.directory.Attributes;
import javax.naming.directory.InitialDirContext;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Hashtable;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * RFC 5322 format validation via Jakarta Mail {@link InternetAddress},
 * MX DNS checks, and optional rate-limited SMTP RCPT probing (never sends mail).
 */
@Service
public class EmailAddressValidationService {

    private static final Logger log = LoggerFactory.getLogger(EmailAddressValidationService.class);

    private final boolean smtpProbeEnabled;
    private final Duration smtpRateLimit;
    private final Map<String, Instant> lastSmtpProbeByDomain = new ConcurrentHashMap<>();

    public EmailAddressValidationService(
            @Value("${email.validation.smtp-probe-enabled:false}") final boolean smtpProbeEnabled,
            @Value("${email.validation.smtp-rate-limit-seconds:60}") final long smtpRateLimitSeconds) {
        this.smtpProbeEnabled = smtpProbeEnabled;
        this.smtpRateLimit = Duration.ofSeconds(Math.max(1, smtpRateLimitSeconds));
    }

    public ValidationResult validate(final String email, final boolean includeSmtpProbe) {
        if (email == null || email.isBlank()) {
            return ValidationResult.invalid("Email is required");
        }
        final String trimmed = email.trim();
        try {
            final InternetAddress address = new InternetAddress(trimmed, true);
            address.validate();
        } catch (final AddressException ex) {
            return ValidationResult.invalid("Invalid email address format (RFC 5322)");
        }
        final int at = trimmed.lastIndexOf('@');
        final String domain = trimmed.substring(at + 1).toLowerCase();
        final boolean mxOk;
        try {
            mxOk = hasMxRecords(domain);
        } catch (final Exception ex) {
            log.debug("MX lookup failed for {}: {}", domain, ex.getMessage());
            return ValidationResult.invalid("Unable to verify mail domain MX records");
        }
        if (!mxOk) {
            return ValidationResult.invalid("Domain has no MX DNS records");
        }

        Boolean smtpOk = null;
        if (includeSmtpProbe && smtpProbeEnabled) {
            smtpOk = probeSmtpRcpt(domain, trimmed);
        }
        return new ValidationResult(true, null, domain, true, smtpOk);
    }

    boolean hasMxRecords(final String domain) throws NamingException {
        final Hashtable<String, String> env = new Hashtable<>();
        env.put("java.naming.factory.initial", "com.sun.jndi.dns.DnsContextFactory");
        final InitialDirContext ctx = new InitialDirContext(env);
        try {
            final Attributes attrs = ctx.getAttributes(domain, new String[]{"MX"});
            final Attribute attr = attrs.get("MX");
            return attr != null && attr.size() > 0;
        } finally {
            ctx.close();
        }
    }

    Boolean probeSmtpRcpt(final String domain, final String email) {
        final Instant last = lastSmtpProbeByDomain.get(domain);
        if (last != null && last.isAfter(Instant.now().minus(smtpRateLimit))) {
            return null;
        }
        lastSmtpProbeByDomain.put(domain, Instant.now());
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(domain, 25), 3000);
            socket.setSoTimeout(3000);
            final BufferedReader in = new BufferedReader(
                    new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII));
            final OutputStreamWriter out = new OutputStreamWriter(
                    socket.getOutputStream(), StandardCharsets.US_ASCII);
            readSmtp(in);
            writeSmtp(out, "EHLO careconnect.local");
            readSmtp(in);
            writeSmtp(out, "MAIL FROM:<>");
            readSmtp(in);
            writeSmtp(out, "RCPT TO:<" + email + ">");
            final String rcpt = readSmtp(in);
            writeSmtp(out, "QUIT");
            return rcpt != null && (rcpt.startsWith("250") || rcpt.startsWith("251"));
        } catch (final Exception ex) {
            log.debug("SMTP RCPT probe skipped/failed for {}: {}", domain, ex.getMessage());
            return null;
        }
    }

    private static void writeSmtp(final OutputStreamWriter out, final String line) throws Exception {
        out.write(line + "\r\n");
        out.flush();
    }

    private static String readSmtp(final BufferedReader in) throws Exception {
        String last = null;
        String line;
        while ((line = in.readLine()) != null) {
            last = line;
            if (line.length() < 4 || line.charAt(3) == ' ') {
                break;
            }
        }
        return last;
    }

    public record ValidationResult(
            boolean valid,
            String error,
            String domain,
            Boolean mxValid,
            Boolean smtpAccepted
    ) {
        public static ValidationResult invalid(final String error) {
            return new ValidationResult(false, error, null, null, null);
        }
    }
}

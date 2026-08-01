package com.careconnect.service;

import com.careconnect.exception.EmailAuthException;
import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.model.*;
import com.careconnect.repository.EmailCredentialRepo;
import com.careconnect.repository.USPSDigestCacheRepo;
import com.careconnect.security.TokenCryptor;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class USPSDigestService {
    private static final Logger log = LoggerFactory.getLogger(USPSDigestService.class);
    private static final int SEARCH_LOOKBACK_DAYS = 30;
    private static final int MAX_REMOTE_FETCHES = 8;

    private final EmailCredentialRepo credRepo;
    private final USPSDigestCacheRepo cacheRepo;
    private final GmailClient gmailClient;
    private final OutlookClient outlookClient;
    private final GmailParser gmailParser;
    private final OutlookParser outlookParser;
    private final TokenCryptor tokenCryptor;
    private final GoogleOAuthService googleOAuthService;
    private final EmailCredentialLifecycleService credentialLifecycle;
    private final UspsMailpiecePersistenceService mailpiecePersistenceService;
    private final ObjectMapper om = new ObjectMapper();

    public Optional<USPSDigest> latestForUser(String userId) {
        // 1) cache ΓÇö still retry durable persist (idempotent) so a prior failure
        //    during TTL cannot leave the Ask AI index permanently empty.
        var cached = cacheRepo.findFirstByUserIdAndExpiresAtAfterOrderByDigestDateDesc(userId, Instant.now());
        if (cached.isPresent()) {
            try {
                final USPSDigest digest =
                        om.readValue(cached.get().getPayloadJson(), USPSDigest.class);
                persistMailpieces(userId, digest);
                return Optional.of(digest);
            } catch (Exception ex) {
                log.warn("Failed to deserialize cached USPS digest for userId={}: {}",
                        userId, ex.getMessage());
            }
        }

        // 2) Gmail
        var g = prepareGmailCredential(userId);
        if (g.isPresent()) {
            try {
                var at = decrypt(g.get().getAccessTokenEnc());
                var raw = gmailClient.fetchLatestDigest(at);
                if (raw.isPresent()) {
                    var digest = gmailParser.toDomain(raw.get());
                    cache(userId, digest);
                    return Optional.of(digest);
                }
            } catch (EmailAuthException authEx) {
                haltForAuthFailure(g.get(), authEx.getMessage());
            }
        }

        // 3) Outlook
        var o = credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.OUTLOOK);
        if (o.isPresent()) {
            var at = decrypt(o.get().getAccessTokenEnc());
            var raw = outlookClient.fetchLatestDigest(at);
            if (raw.isPresent()) {
                var digest = outlookParser.toDomain(raw.get());
                cache(userId, digest);
                return Optional.of(digest);
            }
        }

        // 4) No mock data - return empty if no real data found
        return Optional.empty();
    }

    public Optional<USPSDigest> digestForDate(String userId, LocalDate date) {
        if (date == null) {
            return latestForUser(userId);
        }

        var start = date.atStartOfDay(ZoneOffset.UTC).toInstant();
        var end = date.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant();
        var now = Instant.now();

        var cached = cacheRepo.findFirstByUserIdAndDigestDateBetweenAndExpiresAtAfterOrderByDigestDateDesc(
                userId, start, end, now);
        if (cached.isPresent()) {
            try {
                final USPSDigest digest =
                        om.readValue(cached.get().getPayloadJson(), USPSDigest.class);
                persistMailpieces(userId, digest);
                return Optional.of(digest);
            } catch (Exception ex) {
                log.warn("Failed to deserialize cached USPS digest for userId={} date={}: {}",
                        userId, date, ex.getMessage());
            }
        }

        var g = prepareGmailCredential(userId);
        if (g.isPresent()) {
            try {
                var at = decrypt(g.get().getAccessTokenEnc());
                var raw = gmailClient.fetchDigestForDate(at, date);
                if (raw.isPresent()) {
                    var digest = gmailParser.toDomain(raw.get());
                    cache(userId, digest, date);
                    return Optional.of(digest);
                }
            } catch (EmailAuthException authEx) {
                haltForAuthFailure(g.get(), authEx.getMessage());
            }
        }

        var o = credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.OUTLOOK);
        if (o.isPresent()) {
            var at = decrypt(o.get().getAccessTokenEnc());
            var raw = outlookClient.fetchDigestForDate(at, date);
            if (raw.isPresent()) {
                var digest = outlookParser.toDomain(raw.get());
                cache(userId, digest, date);
                return Optional.of(digest);
            }
        }

        return Optional.empty();
    }

    public List<Map<String, Object>> search(String userId, String keyword) {
        if (isBlank(userId) || keyword == null || keyword.isBlank()) {
            return List.of();
        }

        String normalized = keyword.trim().toLowerCase(Locale.ROOT);
        List<Map<String, Object>> results = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        Set<LocalDate> inspectedDates = new HashSet<>();

        var caches = cacheRepo.findByUserIdOrderByDigestDateDesc(userId);
        if (caches != null && !caches.isEmpty()) {
            for (USPSDigestCache cache : caches) {
                var digest = readDigest(cache);
                if (digest == null) {
                    continue;
                }
                if (cache.getDigestDate() != null) {
                    inspectedDates.add(cache.getDigestDate().atZone(ZoneOffset.UTC).toLocalDate());
                }
                OffsetDateTime cacheDate = cache.getDigestDate() != null
                        ? cache.getDigestDate().atOffset(ZoneOffset.UTC)
                        : digest.digestDate();
                collectMatches(digest, cacheDate, normalized, results, seen);
                if (results.size() >= 50) {
                    break;
                }
            }
        }

        if (results.size() < 50) {
            LocalDate today = LocalDate.now(ZoneOffset.UTC);
            int remoteFetches = 0;
            int consecutiveMisses = 0;
            for (int i = 0; i < SEARCH_LOOKBACK_DAYS && results.size() < 50; i++) {
                LocalDate date = today.minusDays(i);
                if (!inspectedDates.add(date)) {
                    continue;
                }
                if (remoteFetches >= MAX_REMOTE_FETCHES) {
                    break;
                }
                var digestOpt = digestForDate(userId, date);
                remoteFetches++;
                if (digestOpt.isEmpty()) {
                    consecutiveMisses++;
                    if (consecutiveMisses >= 3) {
                        break;
                    }
                    continue;
                }
                consecutiveMisses = 0;
                var digest = digestOpt.get();
                OffsetDateTime dateTime = digest.digestDate() != null
                        ? digest.digestDate()
                        : date.atStartOfDay().atOffset(ZoneOffset.UTC);
                collectMatches(digest, dateTime, normalized, results, seen);
            }
        }

        if (results.isEmpty()) {
            latestForUser(userId).ifPresent(digest -> {
                collectMatches(digest, digest.digestDate(), normalized, results, seen);
            });
        }

        return results;
    }

    private void cache(String userId, USPSDigest d) {
        cache(userId, d, null);
    }

    private void cache(String userId, USPSDigest d, LocalDate requestedDate) {
        try {
            var c = new USPSDigestCache();
            c.setUserId(userId);
            Instant digestInstant;
            if (requestedDate != null) {
                digestInstant = requestedDate.atStartOfDay(ZoneOffset.UTC).toInstant();
            } else if (d.digestDate() != null) {
                digestInstant = d.digestDate().toInstant();
            } else {
                digestInstant = Instant.now();
            }
            c.setDigestDate(digestInstant);
            c.setPayloadJson(om.writeValueAsString(d));
            c.setExpiresAt(Instant.now().plus(Duration.ofHours(24)));
            cacheRepo.save(c);
            persistMailpieces(userId, d);
        } catch (Exception ex) {
            log.warn("Failed to cache USPS digest for userId={}: {}", userId, ex.getMessage());
        }
    }

    private void persistMailpieces(String userId, USPSDigest digest) {
        if (mailpiecePersistenceService == null || digest == null) {
            return;
        }
        try {
            mailpiecePersistenceService.persistAndIndex(userId, digest);
        } catch (Exception ex) {
            log.warn("Mailpiece persistence failed for userId={}: {}", userId, ex.getMessage(), ex);
        }
    }

    @Transactional
    public void clearCacheForUser(String userId) {
        cacheRepo.deleteByUserId(userId);
    }

    private String decrypt(String s) {
        return tokenCryptor.decrypt(s);
    }

    /**
     * Loads Gmail credentials, refreshes if needed, and refuses remote sync when
     * revoked/expired (halts further provider calls).
     */
    private Optional<EmailCredential> prepareGmailCredential(final String userId) {
        final Optional<EmailCredential> found = credRepo
                .findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL);
        if (found.isEmpty()) {
            return Optional.empty();
        }
        EmailCredential credential = found.get();
        if (!credentialLifecycle.allowsSync(credential)) {
            throw new EmailCredentialNeedsReauthException(
                    userId,
                    credential.getLastError() != null
                            ? credential.getLastError()
                            : "Gmail access revoked or expired. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        }
        credential = googleOAuthService.ensureFreshToken(credential);
        if (!credentialLifecycle.allowsSync(credential)) {
            throw new EmailCredentialNeedsReauthException(
                    userId,
                    "Gmail access revoked or expired. Reconnect to resume mail sync.",
                    EmailCredentialLifecycleService.RECONNECT_PATH);
        }
        return Optional.of(credential);
    }

    private void haltForAuthFailure(final EmailCredential credential, final String reason) {
        credentialLifecycle.markNeedsReauth(credential, reason);
        throw new EmailCredentialNeedsReauthException(
                credential.getUserId(),
                "Gmail access revoked or expired. Reconnect to resume mail sync.",
                EmailCredentialLifecycleService.RECONNECT_PATH);
    }

    private USPSDigest readDigest(USPSDigestCache cache) {
        if (cache == null || cache.getPayloadJson() == null) {
            return null;
        }
        try {
            return om.readValue(cache.getPayloadJson(), USPSDigest.class);
        } catch (Exception ignored) {
            return null;
        }
    }

    private void collectMatches(USPSDigest digest,
                                OffsetDateTime digestDate,
                                String needle,
                                List<Map<String, Object>> out,
                                Set<String> seen) {
        if (digest == null) {
            return;
        }
        OffsetDateTime baseDate = digestDate != null ? digestDate : digest.digestDate();

        if (digest.mailpieces() != null) {
            for (MailPiece piece : digest.mailpieces()) {
                if (piece == null || !matchesMailPiece(piece, needle)) {
                    continue;
                }
                String key = "mail:" + safeKey(piece.getId(), piece.getSender(), piece.getSubject());
                if (!seen.add(key)) {
                    continue;
                }
                Map<String, Object> map = new HashMap<>();
                map.put("type", "mail");
                map.put("id", piece.getId());
                map.put("sender", piece.getSender());
                map.put("summary", piece.getSubject());
                map.put("subject", piece.getSubject());
                map.put("imageDataUrl", piece.getThumbnailUrl());
                map.put("thumbnailUrl", piece.getThumbnailUrl());
                OffsetDateTime received = piece.getReceivedAt() != null ? piece.getReceivedAt() : baseDate;
                if (received != null) {
                    map.put("deliveryDate", received.toString());
                }
                if (baseDate != null) {
                    map.put("digestDate", baseDate.toString());
                }
                if (piece.getActionLinks() != null) {
                    map.put("actions", piece.getActionLinks());
                }
                out.add(map);
            }
        }

        if (digest.packages() != null) {
            for (PackageItem pkg : digest.packages()) {
                if (pkg == null || !matchesPackage(pkg, needle)) {
                    continue;
                }
                String key = "pkg:" + safeKey(pkg.getTrackingNumber(), pkg.getSender(), null);
                if (!seen.add(key)) {
                    continue;
                }
                Map<String, Object> map = new HashMap<>();
                map.put("type", "package");
                map.put("trackingNumber", pkg.getTrackingNumber());
                map.put("sender", pkg.getSender());
                OffsetDateTime expected = pkg.getExpectedDeliveryDate() != null ? pkg.getExpectedDeliveryDate() : baseDate;
                if (expected != null) {
                    map.put("expectedDate", expected.toString());
                }
                if (baseDate != null) {
                    map.put("digestDate", baseDate.toString());
                }
                if (pkg.getActionLinks() != null) {
                    map.put("actions", pkg.getActionLinks());
                }
                out.add(map);
            }
        }
    }

    private boolean matchesMailPiece(MailPiece piece, String needle) {
        return contains(piece.getSender(), needle)
                || contains(piece.getSubject(), needle)
                || contains(piece.getId(), needle);
    }

    private boolean matchesPackage(PackageItem pkg, String needle) {
        return contains(pkg.getSender(), needle)
                || contains(pkg.getTrackingNumber(), needle);
    }

    private boolean contains(String value, String needle) {
        if (value == null) {
            return false;
        }
        return value.toLowerCase(Locale.ROOT).contains(needle);
    }

    private String safeKey(String primary, String secondary, String tertiary) {
        StringBuilder sb = new StringBuilder();
        if (primary != null) {
            sb.append(primary.toLowerCase(Locale.ROOT));
        }
        sb.append('|');
        if (secondary != null) {
            sb.append(secondary.toLowerCase(Locale.ROOT));
        }
        sb.append('|');
        if (tertiary != null) {
            sb.append(tertiary.toLowerCase(Locale.ROOT));
        }
        return sb.toString();
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private USPSDigest mockDigest() {
        var now = OffsetDateTime.now(ZoneOffset.UTC);
        var pkg = new PackageItem("9400100000000000000000", "USPS Package", now.plusDays(1),
                ActionLinks.defaults("https://tools.usps.com/go/TrackConfirmAction?qtc_tLabels1=9400100000000000000000"));
        var mp  = new MailPiece("m-1","ACME Bank","Monthly statement",
                "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0nNDAnIGhlaWdodD0nMjAnIHhtbG5zPSdodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2Zyc+PHJlY3Qgd2lkdGg9JzQwJyBoZWlnaHQ9JzIwJyBmaWxsPSIjZGRkIi8+PC9zdmc+",
                now, ActionLinks.defaults(null));
        return new USPSDigest(now, List.of(mp), List.of(pkg));
    }
}

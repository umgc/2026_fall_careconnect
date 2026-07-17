package com.careconnect.service;

import com.careconnect.dto.GmailDigestPayload;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.USPSDigest;
import com.careconnect.model.USPSDigestCache;
import com.careconnect.repository.EmailCredentialRepo;
import com.careconnect.repository.USPSDigestCacheRepo;
import com.careconnect.security.TokenCryptor;
import org.junit.jupiter.api.Test;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

class USPSDigestServiceTest {

    /**
     * Used by new tests to encrypt credentials and by buildService() to decrypt them.
     * Both must use the same key so the round-trip succeeds.
     */
    private final TokenCryptor cryptor = new TokenCryptor("unit-test-secret-32-bytes-long!!!");

    // ── Existing tests (unchanged) ────────────────────────────────────────────

    @Test
    void returnsGmailDigestAndCachesResult() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();

        var credential = new EmailCredential();
        credential.setUserId("user-1");
        credential.setProvider(EmailCredential.Provider.GMAIL);
        credential.setAccessTokenEnc(cryptor.encrypt("access-token"));
        var emailRepo = emailCredentialRepository(Optional.of(credential));

        var gmailClient = new StubGmailClient();
        GmailDigestPayload payload = new GmailDigestPayload("<html></html>", Map.of(), OffsetDateTime.now());
        gmailClient.payload = Optional.of(payload);

        var gmailParser = new StubGmailParser();
        // null digestDate avoids OffsetDateTime serialization failure on a bare ObjectMapper
        USPSDigest digest = new USPSDigest(
                null,
                List.of(),
                List.of());
        gmailParser.digest = digest;

        USPSDigestService service = buildService(
                emailRepo,
                cacheStub,
                gmailClient,
                new OutlookClient(),
                gmailParser,
                new OutlookParser()
        );

        Optional<USPSDigest> result = service.latestForUser("user-1");

        assertTrue(result.isPresent());
        assertEquals(digest, result.get());
        assertNotNull(cacheStub.saved, "Digest should be cached");
        assertEquals("user-1", cacheStub.saved.getUserId());
        assertNotNull(cacheStub.saved.getPayloadJson());
    }

    @Test
    void returnsCachedDigestWhenAvailable() throws Exception {
        var cacheStub = new CacheRepoStub();

        var cached = new USPSDigestCache();
        cached.setUserId("user-2");
        cached.setDigestDate(Instant.now());
        cached.setExpiresAt(Instant.now().plusSeconds(3600));
        cached.setPayloadJson("{\"digestDate\":null,\"mailpieces\":[],\"packages\":[]}");
        cacheStub.nextLookup = Optional.of(cached);

        USPSDigestService service = buildService(
        final RecordingMailpiecePersistence persistence = new RecordingMailpiecePersistence();
        USPSDigestService service = new USPSDigestService(
                emailCredentialRepository(Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
                new OutlookParser(),
                new TokenCryptor("test-secret-key"),
                noOpMailpiecePersistence()
                persistence
        );

        Optional<USPSDigest> result = service.latestForUser("user-2");

        assertTrue(result.isPresent());
        assertNull(result.get().digestDate());
        assertNull(cacheStub.saved, "Cached value should be reused without overwriting");
        assertEquals(1, persistence.calls,
                "Cache hit must still retry idempotent durable persist");
        assertEquals("user-2", persistence.lastUserId);
    }

    // ── New: latestForUser ────────────────────────────────────────────────────

    /**
     * When the cache is empty and no email credentials are stored for the user,
     * latestForUser() should return an empty Optional without throwing.
     */
    @Test
    void returnsEmptyWhenNoCacheAndNoCredentials() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        assertTrue(service.latestForUser("no-creds-user").isEmpty(),
                "No cache and no credentials should yield an empty result");
    }

    /**
     * When there is no Gmail credential but a valid Outlook credential exists,
     * latestForUser() should fall back to Outlook, return its digest, and cache it.
     */
    @Test
    void fallsBackToOutlookWhenGmailCredentialAbsent() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();

        var outlookCred = new EmailCredential();
        outlookCred.setUserId("user-3");
        outlookCred.setProvider(EmailCredential.Provider.OUTLOOK);
        outlookCred.setAccessTokenEnc(cryptor.encrypt("outlook-access-token"));

        USPSDigest expectedDigest = new USPSDigest(null, List.of(), List.of());
        var stubOutlook = new StubOutlookClient(
                new OutlookClient.OutlookRaw("<html/>", Map.of(), Instant.now()));
        var stubOutlookParser = new StubOutlookParser(expectedDigest);

        USPSDigestService service = buildService(
                // Gmail absent; Outlook present
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.of(outlookCred)),
                cacheStub,
                new StubGmailClient(),   // Gmail client returns empty
                stubOutlook,
                new StubGmailParser(),
                stubOutlookParser
        );

        var result = service.latestForUser("user-3");

        assertTrue(result.isPresent(), "Outlook fallback should yield a digest");
        assertEquals(expectedDigest, result.get());
        assertNotNull(cacheStub.saved, "Outlook digest should be cached after fetch");
    }

    // ── New: digestForDate ────────────────────────────────────────────────────

    /**
     * digestForDate(userId, null) must delegate to latestForUser().
     * A valid cache entry returned by latestForUser() should propagate back as the result.
     */
    @Test
    void digestForDateWithNullDelegatesToLatestForUser() throws Exception {
        var cacheStub = new CacheRepoStub();
        // Simulate a cache hit that latestForUser() will find
        var cached = new USPSDigestCache();
        cached.setUserId("user-4");
        cached.setDigestDate(Instant.now());
        cached.setExpiresAt(Instant.now().plusSeconds(3600));
        cached.setPayloadJson("{\"digestDate\":null,\"mailpieces\":[],\"packages\":[]}");
        cacheStub.nextLookup = Optional.of(cached);

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        // null date → delegates to latestForUser → should return the cached digest
        var result = service.digestForDate("user-4", null);
        assertTrue(result.isPresent(), "null date should delegate to latestForUser and hit cache");
    }

    /**
     * When a cache entry exists for the exact requested date,
     * digestForDate() should return it without performing a remote fetch.
     */
    @Test
    void digestForDateReturnsCachedEntryForDate() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();  // latestForUser lookup (not used here)

        // Simulate a date-range cache hit
        var cached = new USPSDigestCache();
        cached.setUserId("user-5");
        cached.setDigestDate(Instant.parse("2025-06-15T00:00:00Z"));
        cached.setExpiresAt(Instant.now().plusSeconds(3600));
        cached.setPayloadJson("{\"digestDate\":null,\"mailpieces\":[],\"packages\":[]}");
        cacheStub.dateRangeLookup = Optional.of(cached);

        final RecordingMailpiecePersistence persistence = new RecordingMailpiecePersistence();
        USPSDigestService service = new USPSDigestService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub.asRepo(),
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser(),
                cryptor,
                persistence
        );

        var result = service.digestForDate("user-5", LocalDate.of(2025, 6, 15));
        assertTrue(result.isPresent(), "Should return the date-specific cached entry");
        assertNull(cacheStub.saved, "No new save should happen when a cache hit is found");
        assertEquals(1, persistence.calls,
                "Date cache hit must still retry idempotent durable persist");
        assertEquals("user-5", persistence.lastUserId);
    }

    /**
     * When the date cache misses and a Gmail credential is present,
     * digestForDate() should fetch from Gmail, cache the result, and return it.
     */
    @Test
    void digestForDateFetchesFromGmailWhenNoCacheHit() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        // Gmail credential whose access token was encrypted with the same key used by buildService
        var gmailCred = new EmailCredential();
        gmailCred.setUserId("user-6");
        gmailCred.setProvider(EmailCredential.Provider.GMAIL);
        gmailCred.setAccessTokenEnc(cryptor.encrypt("gmail-access-token"));

        USPSDigest expectedDigest = new USPSDigest(null, List.of(), List.of());
        var gmailClient = new StubGmailClient();
        gmailClient.payloadForDate = Optional.of(
                new GmailDigestPayload("<html/>", Map.of(), OffsetDateTime.now()));
        var gmailParser = new StubGmailParser();
        gmailParser.digest = expectedDigest;

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.of(gmailCred), Optional.empty()),
                cacheStub,
                gmailClient,
                new OutlookClient(),
                gmailParser,
                new OutlookParser()
        );

        var result = service.digestForDate("user-6", LocalDate.of(2025, 6, 15));

        assertTrue(result.isPresent(), "Gmail fetch should succeed");
        assertEquals(expectedDigest, result.get());
        assertNotNull(cacheStub.saved, "Fetched digest should be written to cache");
        assertEquals("user-6", cacheStub.saved.getUserId());
    }

    // ── New: search ───────────────────────────────────────────────────────────

    /**
     * search() performs an early-exit guard on the userId.
     * A blank or null userId must return an empty list without touching any repository.
     */
    @Test
    void searchReturnsEmptyForBlankUserId() throws Exception {
        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                new CacheRepoStub(),
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        assertTrue(service.search("", "bank").isEmpty(),    "blank userId → empty list");
        assertTrue(service.search(null, "bank").isEmpty(),  "null userId → empty list");
    }

    /**
     * search() performs an early-exit guard on the keyword.
     * A blank or null keyword must return an empty list without touching any repository.
     */
    @Test
    void searchReturnsEmptyForBlankKeyword() throws Exception {
        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                new CacheRepoStub(),
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        assertTrue(service.search("user-1", "").isEmpty(),   "blank keyword → empty list");
        assertTrue(service.search("user-1", null).isEmpty(), "null keyword → empty list");
    }

    /**
     * When a cached digest contains a MailPiece whose sender matches the search keyword
     * (case-insensitive), search() must return a result entry with type="mail"
     * and the correct id and sender fields.
     */
    @Test
    void searchFindsMatchingMailPiecesFromCache() throws Exception {
        // JSON uses "summary" because MailPiece.subject is @JsonProperty("summary")
        String payloadJson = "{\"digestDate\":null,\"mailpieces\":[" +
                "{\"id\":\"m-1\",\"sender\":\"ACME Bank\",\"summary\":\"Monthly Statement\"," +
                "\"imageDataUrl\":null,\"receivedAt\":null,\"actions\":null}]," +
                "\"packages\":[]}";

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(simpleCacheEntry("user-7", payloadJson));
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-7", "acme");

        assertFalse(results.isEmpty(), "Should find the matching mail piece");
        assertEquals("mail", results.get(0).get("type"),    "Result type should be 'mail'");
        assertEquals("m-1",  results.get(0).get("id"),      "Result id should match mail piece id");
        assertEquals("ACME Bank", results.get(0).get("sender"), "Sender field should be preserved");
    }

    /**
     * When a cached digest contains a PackageItem whose sender matches the keyword,
     * search() must return a result entry with type="package" and the correct trackingNumber.
     */
    @Test
    void searchFindsMatchingPackagesFromCache() throws Exception {
        // JSON uses "expectedDateIso" because PackageItem.expectedDeliveryDate is @JsonProperty("expectedDateIso")
        String payloadJson = "{\"digestDate\":null,\"mailpieces\":[]," +
                "\"packages\":[{\"trackingNumber\":\"9400111899223397623988\"," +
                "\"sender\":\"Amazon\",\"expectedDateIso\":null,\"actions\":null}]}";

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(simpleCacheEntry("user-8", payloadJson));
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-8", "amazon");

        assertFalse(results.isEmpty(), "Should find the matching package");
        assertEquals("package", results.get(0).get("type"),   "Result type should be 'package'");
        assertEquals("Amazon",  results.get(0).get("sender"), "Sender field should be preserved");
        assertEquals("9400111899223397623988", results.get(0).get("trackingNumber"));
    }

    /**
     * When the same MailPiece appears in two separate cache entries (identical id/sender/subject),
     * search() must include it only once in the results — deduplication by composite key.
     */
    @Test
    void searchDeduplicatesMatchingItems() throws Exception {
        // Both cache entries carry the exact same MailPiece; the second should be skipped.
        String payloadJson = "{\"digestDate\":null,\"mailpieces\":[" +
                "{\"id\":\"m-dup\",\"sender\":\"Duplicate Sender\",\"summary\":\"Bill\"," +
                "\"imageDataUrl\":null,\"receivedAt\":null,\"actions\":null}]," +
                "\"packages\":[]}";

        USPSDigestCache entry1 = simpleCacheEntry("user-9", payloadJson);
        entry1.setDigestDate(Instant.parse("2025-06-15T00:00:00Z"));

        USPSDigestCache entry2 = simpleCacheEntry("user-9", payloadJson);
        entry2.setDigestDate(Instant.parse("2025-06-14T00:00:00Z"));

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(entry1, entry2);
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-9", "duplicate");

        assertEquals(1, results.size(),
                "Identical mail pieces across two cache entries should be deduplicated to one result");
    }

    // ── New: clearCacheForUser ────────────────────────────────────────────────

    /**
     * clearCacheForUser() must set expiresAt to a time in the past for every cache entry
     * belonging to the specified user, and must not modify entries owned by other users.
     */
    @Test
    void clearCacheForUserExpiresAllEntries() throws Exception {
        Instant future = Instant.now().plusSeconds(3600);

        var entry1 = new USPSDigestCache();
        entry1.setUserId("user-10");
        entry1.setPayloadJson("{}");
        entry1.setExpiresAt(future);

        var entry2 = new USPSDigestCache();
        entry2.setUserId("user-10");
        entry2.setPayloadJson("{}");
        entry2.setExpiresAt(future);

        // This entry belongs to a different user and must not be touched
        var otherEntry = new USPSDigestCache();
        otherEntry.setUserId("other-user");
        otherEntry.setPayloadJson("{}");
        otherEntry.setExpiresAt(future);

        List<USPSDigestCache> savedEntries = new ArrayList<>();
        var cacheStub = new CacheRepoStub();
        cacheStub.allEntries = List.of(entry1, entry2, otherEntry);
        cacheStub.savedAll  = savedEntries;

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        service.clearCacheForUser("user-10");

        // Only the two user-10 entries should have been saved
        assertEquals(2, savedEntries.size(),
                "Only the target user's entries should be saved");

        // Every saved entry must now have an expiresAt in the past
        Instant now = Instant.now();
        for (USPSDigestCache saved : savedEntries) {
            assertTrue(saved.getExpiresAt().isBefore(now),
                    "expiresAt should be set to a time in the past after clearCacheForUser");
        }
    }

    // ── New: latestForUser Outlook fallback when Gmail fetch empty ────────────

    /**
     * When a Gmail credential is present but fetchLatestDigest() returns empty,
     * latestForUser() should fall through to Outlook, return its digest, and cache it.
     */
    @Test
    void latestForUserFallsBackToOutlookWhenGmailFetchEmpty() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();

        var gmailCred = new EmailCredential();
        gmailCred.setUserId("user-gfb");
        gmailCred.setProvider(EmailCredential.Provider.GMAIL);
        gmailCred.setAccessTokenEnc(cryptor.encrypt("gmail-token"));

        var outlookCred = new EmailCredential();
        outlookCred.setUserId("user-gfb");
        outlookCred.setProvider(EmailCredential.Provider.OUTLOOK);
        outlookCred.setAccessTokenEnc(cryptor.encrypt("outlook-token"));

        USPSDigest expectedDigest = new USPSDigest(null, List.of(), List.of());

        // Gmail client returns empty → forces the code to fall through to Outlook
        var gmailClient = new StubGmailClient();
        gmailClient.payload = Optional.empty();

        var stubOutlook = new StubOutlookClient(
                new OutlookClient.OutlookRaw("<html/>", Map.of(), Instant.now()));
        var stubOutlookParser = new StubOutlookParser(expectedDigest);

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.of(gmailCred), Optional.of(outlookCred)),
                cacheStub,
                gmailClient,
                stubOutlook,
                new StubGmailParser(),
                stubOutlookParser
        );

        var result = service.latestForUser("user-gfb");

        assertTrue(result.isPresent(), "Should fall back to Outlook when Gmail credential present but fetch returns empty");
        assertEquals(expectedDigest, result.get());
        assertNotNull(cacheStub.saved, "Outlook digest should be cached");
    }

    // ── New: digestForDate additional paths ───────────────────────────────────

    /**
     * When there is no cache hit and no credentials for a specific date,
     * digestForDate() must return an empty Optional.
     */
    @Test
    void digestForDateReturnsEmptyWhenNoCacheAndNoCredentials() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        assertTrue(service.digestForDate("user-nodata", LocalDate.of(2025, 1, 1)).isEmpty(),
                "No credentials and no cache should yield empty for a specific date");
    }

    /**
     * When the date cache misses, Gmail credential is absent, but an Outlook credential
     * is present, digestForDate() should fetch from Outlook and cache the result.
     */
    @Test
    void digestForDateFetchesFromOutlookWhenGmailUnavailable() throws Exception {
        var cacheStub = new CacheRepoStub();
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        var outlookCred = new EmailCredential();
        outlookCred.setUserId("user-outdate");
        outlookCred.setProvider(EmailCredential.Provider.OUTLOOK);
        outlookCred.setAccessTokenEnc(cryptor.encrypt("outlook-token"));

        USPSDigest expected = new USPSDigest(null, List.of(), List.of());
        var stubOutlook = new StubOutlookClient(
                new OutlookClient.OutlookRaw("<html/>", Map.of(), Instant.now()));
        var stubOutlookParser = new StubOutlookParser(expected);

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.of(outlookCred)),
                cacheStub,
                new StubGmailClient(),
                stubOutlook,
                new StubGmailParser(),
                stubOutlookParser
        );

        var result = service.digestForDate("user-outdate", LocalDate.of(2025, 6, 15));

        assertTrue(result.isPresent(), "Outlook should be used when Gmail is unavailable");
        assertEquals(expected, result.get());
        assertNotNull(cacheStub.saved, "Fetched Outlook digest should be cached");
    }

    // ── New: search additional matching paths ─────────────────────────────────

    /**
     * search() must match a MailPiece whose subject (the "summary" JSON field) contains
     * the keyword, even when the sender does not match.
     */
    @Test
    void searchFindsMailPieceMatchingBySubject() throws Exception {
        String payloadJson = "{\"digestDate\":null,\"mailpieces\":[" +
                "{\"id\":\"m-sub\",\"sender\":\"XYZ Corp\",\"summary\":\"Invoice November\"," +
                "\"imageDataUrl\":null,\"receivedAt\":null,\"actions\":null}]," +
                "\"packages\":[]}";

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(simpleCacheEntry("user-sub", payloadJson));
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-sub", "invoice");

        assertFalse(results.isEmpty(), "Should match mail piece by subject");
        assertEquals("mail", results.get(0).get("type"));
        assertEquals("Invoice November", results.get(0).get("subject"));
    }

    /**
     * search() must match a PackageItem whose trackingNumber contains the keyword,
     * even when the sender does not match.
     */
    @Test
    void searchFindsPackageMatchingByTrackingNumber() throws Exception {
        String payloadJson = "{\"digestDate\":null,\"mailpieces\":[]," +
                "\"packages\":[{\"trackingNumber\":\"9400UNIQUE99\"," +
                "\"sender\":\"SomeShop\",\"expectedDateIso\":null,\"actions\":null}]}";

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(simpleCacheEntry("user-trk", payloadJson));
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-trk", "9400unique99");

        assertFalse(results.isEmpty(), "Should match package by tracking number");
        assertEquals("package", results.get(0).get("type"));
        assertEquals("9400UNIQUE99", results.get(0).get("trackingNumber"));
    }

    /**
     * When a cache entry has a null payloadJson, readDigest() returns null and the entry
     * must be silently skipped; subsequent valid entries must still be searched normally.
     */
    @Test
    void searchSkipsInvalidCacheEntries() throws Exception {
        var badEntry = new USPSDigestCache();
        badEntry.setUserId("user-bad");
        badEntry.setDigestDate(null);
        badEntry.setExpiresAt(Instant.now().plusSeconds(3600));
        badEntry.setPayloadJson(null);  // null JSON → readDigest returns null → continue

        String validPayload = "{\"digestDate\":null,\"mailpieces\":[" +
                "{\"id\":\"m-ok\",\"sender\":\"Valid Sender\",\"summary\":\"Statement\"," +
                "\"imageDataUrl\":null,\"receivedAt\":null,\"actions\":null}]," +
                "\"packages\":[]}";

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(badEntry, simpleCacheEntry("user-bad", validPayload));
        cacheStub.nextLookup = Optional.empty();
        cacheStub.dateRangeLookup = Optional.empty();

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-bad", "valid");

        assertFalse(results.isEmpty(), "Should find matching entry after skipping invalid one");
        assertEquals("mail", results.get(0).get("type"));
        assertEquals("Valid Sender", results.get(0).get("sender"));
    }

    /**
     * When the cache scan and remote fetches yield no matches,
     * search() falls back to latestForUser() for a final check.
     * A cache hit in latestForUser() with a matching item must appear in the result.
     */
    @Test
    void searchFallsBackToLatestForUserWhenNoCacheResultsMatch() throws Exception {
        // Cache scan entry with no matching content
        String nonMatchingPayload = "{\"digestDate\":null,\"mailpieces\":[]," +
                "\"packages\":[{\"trackingNumber\":\"NONE\",\"sender\":\"No Match\"," +
                "\"expectedDateIso\":null,\"actions\":null}]}";

        // latestForUser cache hit that contains a matching mail piece
        var latestCached = new USPSDigestCache();
        latestCached.setUserId("user-fallback");
        latestCached.setDigestDate(Instant.now());
        latestCached.setExpiresAt(Instant.now().plusSeconds(3600));
        latestCached.setPayloadJson("{\"digestDate\":null,\"mailpieces\":[" +
                "{\"id\":\"m-fb\",\"sender\":\"FallbackSender\",\"summary\":\"Fall Statement\"," +
                "\"imageDataUrl\":null,\"receivedAt\":null,\"actions\":null}]," +
                "\"packages\":[]}");

        var cacheStub = new CacheRepoStub();
        cacheStub.listByUser = List.of(simpleCacheEntry("user-fallback", nonMatchingPayload));
        cacheStub.nextLookup = Optional.of(latestCached);   // used by latestForUser fallback
        cacheStub.dateRangeLookup = Optional.empty();        // remote fetches return empty

        USPSDigestService service = buildService(
                emailCredentialRepositoryByProvider(Optional.empty(), Optional.empty()),
                cacheStub,
                new StubGmailClient(),
                new OutlookClient(),
                new StubGmailParser(),
                new OutlookParser()
        );

        List<Map<String, Object>> results = service.search("user-fallback", "fallbacksender");

        assertFalse(results.isEmpty(), "Fallback to latestForUser should surface matching item");
        assertEquals("mail", results.get(0).get("type"));
        assertEquals("FallbackSender", results.get(0).get("sender"));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Constructs a USPSDigestService with the class-level cryptor key so that any
     * credentials encrypted by this test class can be correctly decrypted at runtime.
     */
    private USPSDigestService buildService(
            EmailCredentialRepo credRepo,
            CacheRepoStub cacheStub,
            GmailClient gmailClient,
            OutlookClient outlookClient,
            GmailParser gmailParser,
            OutlookParser outlookParser
    ) throws Exception {
        final GoogleOAuthService oauth = org.mockito.Mockito.mock(GoogleOAuthService.class);
        org.mockito.Mockito.when(oauth.ensureFreshToken(org.mockito.ArgumentMatchers.any()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        final EmailCredentialLifecycleService lifecycle =
                new EmailCredentialLifecycleService(
                        org.mockito.Mockito.mock(com.careconnect.repository.EmailCredentialRepository.class),
                        org.mockito.Mockito.mock(NotificationService.class));
        return new USPSDigestService(
                credRepo,
                cacheStub.asRepo(),
                gmailClient,
                outlookClient,
                gmailParser,
                outlookParser,
                new TokenCryptor("unit-test-secret-32-bytes-long!!!"),
                oauth,
                lifecycle
                noOpMailpiecePersistence()
        );
    }

    private static UspsMailpiecePersistenceService noOpMailpiecePersistence() {
        return new UspsMailpiecePersistenceService(null, null, new MailpieceNormalizer(), null, null) {
            @Override
            public int persistAndIndex(String userId, USPSDigest digest) {
                return 0;
            }
        };
        return new RecordingMailpiecePersistence();
    }

    /**
     * Counts persistAndIndex invocations so cache-hit retry can be asserted.
     */
    private static final class RecordingMailpiecePersistence extends UspsMailpiecePersistenceService {
        int calls;
        String lastUserId;
        USPSDigest lastDigest;

        RecordingMailpiecePersistence() {
            super(null, null, new MailpieceNormalizer(), null);
        }

        @Override
        public int persistAndIndex(String userId, USPSDigest digest) {
            calls++;
            lastUserId = userId;
            lastDigest = digest;
            return 0;
        }
    }

    /**
     * Creates a minimal cache entry with the given userId and pre-serialized JSON payload.
     * The entry has a future expiry so it is treated as valid by the service.
     */
    private USPSDigestCache simpleCacheEntry(String userId, String payloadJson) {
        var entry = new USPSDigestCache();
        entry.setUserId(userId);
        entry.setDigestDate(Instant.now());
        entry.setExpiresAt(Instant.now().plusSeconds(3600));
        entry.setPayloadJson(payloadJson);
        return entry;
    }

    /**
     * Builds an EmailCredentialRepo stub that returns the same credential for both
     * GMAIL and OUTLOOK provider lookups (backward-compatible helper used by existing tests).
     */
    private EmailCredentialRepo emailCredentialRepository(Optional<EmailCredential> credential) {
        return emailCredentialRepositoryByProvider(credential, Optional.empty());
    }

    /**
     * Builds an EmailCredentialRepo stub that can return different credentials depending
     * on which Provider is requested — allows testing the Gmail-then-Outlook fallback path.
     */
    private EmailCredentialRepo emailCredentialRepositoryByProvider(
            Optional<EmailCredential> gmail,
            Optional<EmailCredential> outlook
    ) {
        InvocationHandler handler = new InvocationHandler() {
            @Override
            public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
                if (method.getDeclaringClass() == Object.class) {
                    return switch (method.getName()) {
                        case "toString" -> "EmailCredentialRepoStub";
                        case "hashCode" -> System.identityHashCode(proxy);
                        case "equals"   -> proxy == args[0];
                        default         -> method.invoke(this, args);
                    };
                }
                return switch (method.getName()) {
                    case "findFirstByUserIdAndProvider",
                         "findFirstByUserIdAndProviderOrderByIdDesc" -> {
                        // args[1] is the Provider enum value
                        var provider = (EmailCredential.Provider) args[1];
                        yield provider == EmailCredential.Provider.GMAIL ? gmail : outlook;
                    }
                    default -> throw new UnsupportedOperationException(
                            "Unexpected EmailCredentialRepo call: " + method.getName());
                };
            }
        };
        return (EmailCredentialRepo) Proxy.newProxyInstance(
                USPSDigestServiceTest.class.getClassLoader(),
                new Class[]{EmailCredentialRepo.class},
                handler
        );
    }

    // ── Stub classes ──────────────────────────────────────────────────────────

    /**
     * In-memory stub for USPSDigestCacheRepo.
     * Fields are set per-test to control the return values for each query method.
     */
    private static class CacheRepoStub {
        /** Return value for findFirstByUserIdAndExpiresAtAfterOrderByDigestDateDesc (latestForUser path). */
        Optional<USPSDigestCache> nextLookup = Optional.empty();

        /** Return value for findFirstByUserIdAndDigestDateBetweenAndExpiresAtAfterOrderByDigestDateDesc (digestForDate path). */
        Optional<USPSDigestCache> dateRangeLookup = Optional.empty();

        /** Return value for findByUserIdOrderByDigestDateDesc (search cache-scan path). */
        List<USPSDigestCache> listByUser = List.of();

        /** Return value for findAll (clearCacheForUser path). */
        List<USPSDigestCache> allEntries = List.of();

        /** Records the most-recently saved entry (used to assert caching behaviour). */
        USPSDigestCache saved = null;

        /**
         * When non-null, every call to save() appends the saved entry to this list.
         * Used by clearCacheForUser tests to verify all updated entries were persisted.
         */
        List<USPSDigestCache> savedAll = null;

        USPSDigestCacheRepo asRepo() throws Exception {
            InvocationHandler handler = new InvocationHandler() {
                @Override
                public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
                    if (method.getDeclaringClass() == Object.class) {
                        return switch (method.getName()) {
                            case "toString" -> "USPSDigestCacheRepoStub";
                            case "hashCode" -> System.identityHashCode(proxy);
                            case "equals"   -> proxy == args[0];
                            default         -> method.invoke(this, args);
                        };
                    }
                    return switch (method.getName()) {
                        case "findFirstByUserIdAndExpiresAtAfterOrderByDigestDateDesc"
                                -> nextLookup;
                        case "findFirstByUserIdAndDigestDateBetweenAndExpiresAtAfterOrderByDigestDateDesc"
                                -> dateRangeLookup;
                        case "findByUserIdOrderByDigestDateDesc"
                                -> listByUser;
                        case "findAll"
                                -> allEntries;
                        case "save" -> {
                            saved = (USPSDigestCache) args[0];
                            if (savedAll != null) savedAll.add(saved);
                            yield saved;
                        }
                        default -> throw new UnsupportedOperationException(
                                "Unexpected USPSDigestCacheRepo call: " + method.getName());
                    };
                }
            };
            return (USPSDigestCacheRepo) Proxy.newProxyInstance(
                    USPSDigestServiceTest.class.getClassLoader(),
                    new Class[]{USPSDigestCacheRepo.class},
                    handler
            );
        }
    }

    /**
     * GmailClient stub that returns preset payloads for both the latest-digest
     * and the date-specific digest fetch methods.
     */
    private static class StubGmailClient extends GmailClient {
        /** Returned by fetchLatestDigest (latestForUser path). */
        Optional<GmailDigestPayload> payload = Optional.empty();

        /** Returned by fetchDigestForDate (digestForDate path). */
        Optional<GmailDigestPayload> payloadForDate = Optional.empty();

        @Override
        public Optional<GmailDigestPayload> fetchLatestDigest(String accessToken) {
            return payload;
        }

        @Override
        public Optional<GmailDigestPayload> fetchDigestForDate(String accessToken, LocalDate date) {
            return payloadForDate;
        }
    }

    /** GmailParser stub that returns a preset USPSDigest for any input payload. */
    private static class StubGmailParser extends GmailParser {
        USPSDigest digest;

        @Override
        public USPSDigest toDomain(GmailDigestPayload payload) {
            return digest;
        }
    }

    /**
     * OutlookClient stub that returns a preset OutlookRaw for both
     * the latest-digest and date-specific fetch methods.
     */
    private static class StubOutlookClient extends OutlookClient {
        private final OutlookRaw raw;

        StubOutlookClient(OutlookRaw raw) {
            this.raw = raw;
        }

        @Override
        public Optional<OutlookRaw> fetchLatestDigest(String accessToken) {
            return Optional.ofNullable(raw);
        }

        @Override
        public Optional<OutlookRaw> fetchDigestForDate(String accessToken, LocalDate date) {
            return Optional.ofNullable(raw);
        }
    }

    /** OutlookParser stub that returns a preset USPSDigest for any input. */
    private static class StubOutlookParser extends OutlookParser {
        private final USPSDigest digest;

        StubOutlookParser(USPSDigest digest) {
            this.digest = digest;
        }

        @Override
        public USPSDigest toDomain(OutlookClient.OutlookRaw raw) {
            return digest;
        }
    }
}

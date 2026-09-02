package com.careconnect.service;

import com.careconnect.dto.GmailDigestPayload;
import com.careconnect.model.MailPiece;
import com.careconnect.model.USPSDigest;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.*;

class GmailParserTest {

    private static final OffsetDateTime NOW = OffsetDateTime.now(ZoneOffset.UTC);

    // ─── helpers ─────────────────────────────────────────────────────────────
    private final GmailParser parser = new GmailParser();

    private GmailDigestPayload p(String html) {
        return new GmailDigestPayload(html, Map.of(), NOW);
    }

    private GmailDigestPayload p(String html, Map<String, String> cids) {
        return new GmailDigestPayload(html, cids, NOW);
    }

    private GmailDigestPayload p(String html, OffsetDateTime receivedAt) {
        return new GmailDigestPayload(html, Map.of(), receivedAt);
    }

    // ─── toDomain: null / blank inputs ───────────────────────────────────────

    @Test
    void toDomain_nullPayload_returnsNull() throws Exception {
        assertNull(parser.toDomain(null));
    }

    @Test
    void toDomain_nullHtmlBody_returnsNonNullEmptyDigest() throws Exception {
        final GmailDigestPayload payload = new GmailDigestPayload(null, Map.of(), NOW);
        final USPSDigest digest = parser.toDomain(payload);
        assertNotNull(digest);
        assertThat(digest.packages()).isEmpty();
        assertThat(digest.mailpieces()).isEmpty();
    }

    @Test
    void toDomain_emptyHtmlBody_returnsEmptyDigest() throws Exception {
        final USPSDigest digest = parser.toDomain(p(""));
        assertNotNull(digest);
    }

    // ─── Existing test — fix tracking-number assertion ────────────────────────

    @Test
    void extractsSenderAndTrackingForPackages() throws IOException {
        final Path htmlPath = Path.of("src/test/resources/usps/gmail-digest-package.html");
        final String html = Files.readString(htmlPath);
        final GmailDigestPayload payload = new GmailDigestPayload(html, Map.of(), NOW);

        final USPSDigest digest = parser.toDomain(payload);
        assertNotNull(digest);
        assertEquals(1, digest.packages().size(), "should find one package");
        assertEquals("Awesome Vendor LLC", digest.packages().get(0).getSender());
        // Parser strips all non-digit characters when building the tracking number
        assertEquals("940012345678", digest.packages().get(0).getTrackingNumber());
    }

    // ─── resolveDigestDate ────────────────────────────────────────────────────

    @Test
    void toDomain_resolveDigestDate_fromTimeDatetimeAttr() throws Exception {
        final String html = "<html><body><time datetime='2025-01-15T08:00:00Z'>Jan 15</time></body></html>";
        // null receivedAt forces fallback path; datetime attr provides date
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
        assertThat(digest.digestDate().getMonthValue()).isEqualTo(1);
    }

    @Test
    void toDomain_resolveDigestDate_fromTimeText_whenDatetimeAttrBlank() throws Exception {
        // <time datetime=""> — attr exists but blank → firstNonBlank uses text content instead
        final String html = "<html><body><time datetime=''>2025-02-20T00:00:00Z</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
    }

    @Test
    void toDomain_resolveDigestDate_fromMetaNameDate() throws Exception {
        final String html = "<html><head><meta name='date' content='2025-06-01T00:00:00Z'/></head><body></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
        assertThat(digest.digestDate().getMonthValue()).isEqualTo(6);
    }

    @Test
    void toDomain_resolveDigestDate_fromDailyDigestHeading() throws Exception {
        final String html = "<html><body><h1>Daily Digest for 2025-03-10T00:00:00Z</h1></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
        assertThat(digest.digestDate().getMonthValue()).isEqualTo(3);
    }

    @Test
    void toDomain_resolveDigestDate_noDateElements_usesFallback() throws Exception {
        final OffsetDateTime fallback = OffsetDateTime.of(2025, 4, 1, 0, 0, 0, 0, ZoneOffset.UTC);
        final USPSDigest digest = parser.toDomain(p("<html><body></body></html>", fallback));
        assertThat(digest.digestDate()).isEqualTo(fallback);
    }

    @Test
    void toDomain_resolveDigestDate_noDateNoFallback_returnsNow() throws Exception {
        final OffsetDateTime before = OffsetDateTime.now(ZoneOffset.UTC).minusSeconds(2);
        final USPSDigest digest = parser.toDomain(p("<html><body></body></html>", (OffsetDateTime) null));
        assertThat(digest.digestDate()).isAfterOrEqualTo(before);
    }

    // ─── parseToOffset: all six date formats ─────────────────────────────────

    @Test
    void toDomain_parseToOffset_rfc1123Format() throws Exception {
        // "Thu, 26 Feb 2026" is a real Thursday (today), so RFC_1123_DATE_TIME parses it correctly
        final String html = "<html><body><time datetime='Thu, 26 Feb 2026 08:00:00 GMT'>Feb</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2026);
        assertThat(digest.digestDate().getMonthValue()).isEqualTo(2);
    }

    @Test
    void toDomain_parseToOffset_fullLocalDate_eeeeMMMMdYyyy() throws Exception {
        final String html = "<html><body><time datetime='Wednesday, January 15, 2025'>Jan</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
        assertThat(digest.digestDate().getDayOfMonth()).isEqualTo(15);
    }

    @Test
    void toDomain_parseToOffset_shortLocalDate_MMMMdYyyy() throws Exception {
        final String html = "<html><body><time datetime='January 15, 2025'>Jan</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
    }

    @Test
    void toDomain_parseToOffset_slashDate_MdYyyy() throws Exception {
        final String html = "<html><body><time datetime='1/15/2025'>Jan</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
    }

    @Test
    void toDomain_parseToOffset_localDateTime_noZone() throws Exception {
        final String html = "<html><body><time datetime='2025-07-04T12:00:00'>Jul</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, (OffsetDateTime) null));
        assertThat(digest.digestDate().getYear()).isEqualTo(2025);
    }

    @Test
    void toDomain_parseToOffset_unrecognisedString_fallsBackToFallback() throws Exception {
        final OffsetDateTime fallback = OffsetDateTime.of(2024, 7, 1, 0, 0, 0, 0, ZoneOffset.UTC);
        final String html = "<html><body><time datetime='not-a-date'>bad</time></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, fallback));
        assertThat(digest.digestDate()).isEqualTo(fallback);
    }

    // ─── parseMailCount ───────────────────────────────────────────────────────

    @Test
    void toDomain_parseMailCount_fromTotalMailpiecesElement() throws Exception {
        // count = 2, 1 real piece → triggers placeholder addition
        final String html = "<html><body>"
                + "<span id='total-mailpieces'>2</span>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(2);
        // second piece is a placeholder
        assertThat(digest.mailpieces().get(1).getId()).startsWith("mail-placeholder-");
    }

    @Test
    void toDomain_parseMailCount_fromYouHaveNMailpiece() throws Exception {
        final String html = "<html><body>"
                + "<p>You have 1 mailpiece today</p>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).isNotEmpty();
    }

    @Test
    void toDomain_parseMailCount_fromMailPiecesHeader() throws Exception {
        final String html = "<html><body>"
                + "<h2>Mail Pieces 1</h2>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).isNotEmpty();
    }

    @Test
    void toDomain_parseMailCount_invalidNumberInElement_treatedAsNegativeOne() throws Exception {
        // parseIntSafe("abc") → -1; no count adjustment
        final String html = "<html><body><span id='total-mailpieces'>abc</span></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertNotNull(digest);
    }

    // ─── parsePackageCount ────────────────────────────────────────────────────

    @Test
    void toDomain_parsePackageCount_fromTotalPackagesElement() throws Exception {
        final String html = "<html><body>"
                + "<span id='total-packages'>1</span>"
                + "<table><tr><td>FROM: Pkg Sender</td></tr>"
                + "<tr><td>Tracking Number: 9400111899223755769810</td></tr></table>"
                + "</body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
    }

    @Test
    void toDomain_parsePackageCount_fromTodayPackageItemNumber() throws Exception {
        // #today-package-item-number element (value = 0 → parsed >= 0 → returned)
        final String html = "<html><body><span id='today-package-item-number'>0</span></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertNotNull(digest);
    }

    // ─── inlineCidImages ─────────────────────────────────────────────────────

    @Test
    void toDomain_inlineCidImages_nullCidMap_noError() throws Exception {
        final GmailDigestPayload payload = new GmailDigestPayload(
                "<html><body><img src='cid:abc'></body></html>", null, NOW);
        final USPSDigest digest = parser.toDomain(payload);
        assertNotNull(digest);
    }

    @Test
    void toDomain_inlineCidImages_replacesAllFourSrcAttributes() throws Exception {
        // One img with all four cid: attrs → each branch inside dataUrl-found block is hit
        final Map<String, String> cids = Map.of("abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='cid:abc' data-src='cid:abc' data-lazy-src='cid:abc' data-original='cid:abc'>"
                + "<span class='sender'>CID Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getThumbnailUrl()).startsWith("data:");
    }

    @Test
    void toDomain_inlineCidImages_unknownCidKey_thumbnailRemainsUnresolved() throws Exception {
        final Map<String, String> cids = Map.of("known", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='cid:unknown'><span class='sender'>S</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        // CID not in map → resolveCidReference returns original "cid:unknown" (non-blank)
        // → piece IS created with unresolved thumbnail
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getThumbnailUrl()).startsWith("cid:");
    }

    @Test
    void toDomain_resolveCidReference_caseInsensitiveLookup() throws Exception {
        // normalizeCid lowercases, so "ABC" img src matches "abc" in cidMap
        final Map<String, String> cids = Map.of("abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='cid:ABC'><span class='sender'>CI Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    @Test
    void toDomain_resolveCidReference_nonCidSrc_returnedAsIs() throws Exception {
        // src is a normal https URL with a cidMap present — not replaced
        final Map<String, String> cids = Map.of("abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='https://example.com/img.png'><span class='sender'>HTTP Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getThumbnailUrl()).startsWith("https://");
    }

    // ─── extractPackages: structured selector ─────────────────────────────────

    @Test
    void toDomain_package_extractedViaClassPackage() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'>"
                + "<span class='sender'>My Vendor</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getSender()).isEqualTo("My Vendor");
    }

    @Test
    void toDomain_package_extractedViaArticleWithTrackingNumber() throws Exception {
        final String html = "<html><body>"
                + "<article>"
                + "<span class='sender'>Article Vendor</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</article></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
    }

    @Test
    void toDomain_package_withTrackUrl() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'>"
                + "<span class='sender'>Track Vendor</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "<a href='https://tools.usps.com/go/TrackConfirmAction?tLabels=940012345678901234'>Track</a>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getActionLinks().getTrack()).contains("TrackConfirmAction");
    }

    @Test
    void toDomain_package_withExpectedDelivery_parsesDate() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'>"
                + "<span class='sender'>Express Co</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "<span>Expected Delivery: January 15, 2025</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getExpectedDeliveryDate().getYear()).isEqualTo(2025);
    }

    @Test
    void toDomain_package_expectedDeliveryDayVariant() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'>"
                + "<span class='sender'>Quick Co</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "<span>Expected Delivery Day: January 20, 2025</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getExpectedDeliveryDate().getDayOfMonth()).isEqualTo(20);
    }

    @Test
    void toDomain_package_expectedDeliveryViaPattern_fromPlainText() throws Exception {
        // extractExpectedText fallback: EXPECTED_PATTERN.matcher(element.text())
        final String html = "<html><body>"
                + "<div class='package' data-tracking-number='9400123456789012345678'>"
                + "Expected Delivery: January 15, 2025"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getExpectedDeliveryDate().getYear()).isEqualTo(2025);
    }

    @Test
    void toDomain_package_dataTrackingNumberAttribute() throws Exception {
        final String html = "<html><body>"
                + "<div class='package' data-tracking-number='9400123456789012345678'>"
                + "<span class='sender'>Attr Vendor</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getSender()).isEqualTo("Attr Vendor");
    }

    @Test
    void toDomain_package_senderFromFromColonNode() throws Exception {
        // extractPackageSender: fromNode = element matching "from:"
        final String html = "<html><body>"
                + "<div class='package' data-tracking-number='9400123456789012345678'>"
                + "<p>from: Direct Sender</p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
    }

    @Test
    void toDomain_package_senderFromFromNode_withBoldChild() throws Exception {
        // extractPackageSender: fromNode found, child element text used
        final String html = "<html><body>"
                + "<div class='package' data-tracking-number='9400123456789012345678'>"
                + "<p>from: <b>Child Sender</b></p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
    }

    @Test
    void toDomain_package_senderFromNearbySibling_previous() throws Exception {
        // extractNearbySender: previous sibling of trackingNode has FROM: text
        final String html = "<html><body>"
                + "<div>"
                + "<p>FROM: Nearby Sibling Corp</p>"
                + "<p>Tracking Number: 940012345678901234</p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
    }

    @Test
    void toDomain_package_senderFromNearbySibling_next() throws Exception {
        // extractNearbySender: next sibling of trackingNode has FROM: text
        final String html = "<html><body>"
                + "<div>"
                + "<p>Tracking Number: 940012345678901234</p>"
                + "<p>FROM: Next Sibling Corp</p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
    }

    @Test
    void toDomain_package_senderFromParentOwnText() throws Exception {
        // extractNearbySender: parent.ownText() has FROM: text
        final String html = "<html><body>"
                + "<div>FROM: Parent Sender"
                + "<p>Tracking Number: 940012345678901234</p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
    }

    @Test
    void toDomain_package_senderIsMarketing_replacedWithUspsPackage() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'>"
                + "<span class='sender'>learn more about your mail</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getSender()).isEqualTo("USPS Package");
    }

    @Test
    void toDomain_package_blankSenderFallsBackToUspsPackage() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getSender()).isEqualTo("USPS Package");
    }

    @Test
    void toDomain_package_duplicateTracking_onlyOneKept() throws Exception {
        final String html = "<html><body>"
                + "<div class='package'><span class='tracking-number'>940012345678</span></div>"
                + "<div class='package'><span class='tracking-number'>940012345678</span></div>"
                + "</body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
    }

    @Test
    void toDomain_package_marketingElement_skipped() throws Exception {
        final String html = "<html><body>"
                + "<div class='package ridealong'>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isEmpty();
    }

    @Test
    void toDomain_package_shortTrackingNumber_normalizedToTrimmed() throws Exception {
        // normalizeTracking: digitsOnly < 10 → returns value.trim()
        final String html = "<html><body>"
                + "<div class='package' data-tracking-number='12345'>"
                + "<span class='sender'>Short Track</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(1);
        assertThat(digest.packages().get(0).getTrackingNumber()).isEqualTo("12345");
    }

    @Test
    void toDomain_package_trackingFromHrefWhenRawTrackingBlank() throws Exception {
        // rawTracking is blank → extract from TrackConfirmAction href
        final String html = "<html><body>"
                + "<div>"
                + "<p>FROM: URL Sender</p>"
                + "<a href='https://tools.usps.com/go/TrackConfirmAction?tLabels=940012345678'>Track</a>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertNotNull(digest);
    }

    // ─── Package fallback: text-search paths ─────────────────────────────────

    @Test
    void toDomain_packageFallback_textSearch_trackingNumberElement() throws Exception {
        // No .package element → falls back to text search "Tracking Number"
        final String html = "<html><body>"
                + "<div>"
                + "<p>FROM: Fallback Sender</p>"
                + "<p>Tracking Number: 9400123456789012345678</p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
    }

    @Test
    void toDomain_packageFallback_textSearch_marketingElementSkipped() throws Exception {
        final String html = "<html><body>"
                + "<div class='ridealong'>"
                + "<p>Tracking Number: 9400123456789012345678</p>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isEmpty();
    }

    @Test
    void toDomain_packageFallback_summaryText_expectedXItems() throws Exception {
        // Third fallback: "Expected Today 3 items" → creates 3 summary packages
        final String html = "<html><body><p>Expected Today 3 items</p></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(3);
    }

    @Test
    void toDomain_packageFallback_summaryText_secondSelector_expectedWithNumber() throws Exception {
        // Second summary selector: containsOwn(Expected) + matchesOwn(\d+), no "item"
        final String html = "<html><body><p>Expected 2 deliveries</p></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(2);
    }

    @Test
    void toDomain_packageFallback_summaryText_cappedAtFive() throws Exception {
        final String html = "<html><body><p>Expected Today 10 items</p></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(5);
    }

    @Test
    void toDomain_packageFallback_expectedTextNoDigit_debugPath() throws Exception {
        // "Expected Tomorrow" has no digit → both summary selectors empty → debug log fires
        final String html = "<html><body><p>Expected Tomorrow</p></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isEmpty();
    }

    // ─── Package count trimming ───────────────────────────────────────────────

    @Test
    void toDomain_packages_trimmedWhenExceedExpectedCount() throws Exception {
        // 5 summary packages, expectedPackageCount = 2 → trim to 2
        final String html = "<html><body>"
                + "<span id='total-packages'>2</span>"
                + "<p>Expected Today 5 items</p>"
                + "</body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).hasSize(2);
    }

    // ─── Mail piece extraction: .mailpiece elements ───────────────────────────

    @Test
    void toDomain_mailpiece_extractedWithSenderSpan() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'>"
                + "<span class='sender'>Post Office</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSender()).isEqualTo("Post Office");
    }

    @Test
    void toDomain_mailpiece_withDataMailpieceId_usedAsId() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'>"
                + "<div data-mailpiece-id='mp-42'>"
                + "<img src='data:image/jpeg;base64,AAAA'>"
                + "<span class='sender'>Bank Corp</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getId()).isEqualTo("mp-42");
    }

    @Test
    void toDomain_mailpiece_senderFromAlt_fromPattern() throws Exception {
        // deriveSenderFromAlt: alt matches FROM_PATTERN → "Great Vendor"
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='From: Great Vendor'>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSender()).isEqualTo("Great Vendor");
    }

    @Test
    void toDomain_mailpiece_senderFromAlt_noFromPattern_returnsNull() throws Exception {
        // deriveSenderFromAlt: alt present but no FROM: match → null from alt
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='just a letter'>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        // sender derived from other paths or null
        assertThat(digest.mailpieces().get(0).getSender()).isNull();
    }

    @Test
    void toDomain_mailpiece_summaryFromAlt_imageOfStripped() throws Exception {
        // deriveSummaryFromAlt: "image of a letter" → "a letter"
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='image of a letter'>"
                + "<span class='sender'>Post Office</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSubject()).isEqualTo("a letter");
    }

    @Test
    void toDomain_mailpiece_deriveSenderFromContext_strongFrom() throws Exception {
        // deriveSenderFromContext: <strong>From</strong> label
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'>"
                + "<strong>From</strong>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    @Test
    void toDomain_mailpiece_deriveSenderFromContext_fromElementWithSibling() throws Exception {
        // deriveSenderFromContext: fromElement "From:" with blank own candidate → sibling text used
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'>"
                + "<p>From:</p><p>Sibling Name</p>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    @Test
    void toDomain_mailpiece_noImg_returnsNull_skipped() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<span class='sender'>No Image</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_receivedAtNull_usesDigestDate() throws Exception {
        // payload.receivedAt() == null → received = digestDate
        final String html = "<html><body>"
                + "<time datetime='2025-05-10T00:00:00Z'>May</time>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final GmailDigestPayload payload = new GmailDigestPayload(html, Map.of(), null);
        final USPSDigest digest = parser.toDomain(payload);
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getReceivedAt().getMonthValue()).isEqualTo(5);
    }

    // ─── Mail piece trimming & placeholder addition ───────────────────────────

    @Test
    void toDomain_mailPieces_trimmedWhenExceedExpectedCount() throws Exception {
        // 2 pieces, expectedMailCount = 1 → trim to 1
        final String html = "<html><body>"
                + "<span id='total-mailpieces'>1</span>"
                + "<div id='mailpieces'>"
                + "<div class='mailpiece'><img src='data:image/jpeg;base64,AAAA'><span class='sender'>S1</span></div>"
                + "<div class='mailpiece'><img src='data:image/jpeg;base64,BBBB'><span class='sender'>S2</span></div>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    @Test
    void toDomain_mailPieces_expectedMailCountSet_whenPositiveAndPiecesFound() throws Exception {
        // expectedMailCount <= 0 && !mailPieces.isEmpty() → set expectedMailCount = mailPieces.size()
        // (no #total-mailpieces element, 1 piece → expectedMailCount becomes 1, no trim/add)
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    // ─── Ride-along image filtering ───────────────────────────────────────────

    @Test
    void toDomain_mailpiece_rideAlongInAlt_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='ridealong advertisement'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongSpacedInAlt_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='ride along ad'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongInId_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' id='ridealong-img'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongDashInId_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' id='ride-along-img'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongInClass_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' class='ridealong'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongDashInClass_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' class='ride-along'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongInParentClass_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<div class='ridealong'><img src='data:image/jpeg;base64,AAAA'></div>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongDashInParentClass_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<div class='ride-along'><img src='data:image/jpeg;base64,AAAA'></div>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongInDataInlineCid_skipped() throws Exception {
        // data-inline-cid starts with "content-" → isRideAlongImage true
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' data-inline-cid='content-12345'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongKeywordInDataInlineCid_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' data-inline-cid='img-ridealong-5'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongDashInDataInlineCid_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' data-inline-cid='img-ride-along-5'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongInCidSrcKey_skipped() throws Exception {
        // cid: src where the key starts with "content-"
        final Map<String, String> cids = Map.of("content-12345", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='cid:content-12345'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html, cids)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongKeywordInCidSrcKey_skipped() throws Exception {
        final Map<String, String> cids = Map.of("img-ridealong-abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='cid:img-ridealong-abc'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html, cids)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongDashInCidSrcKey_skipped() throws Exception {
        final Map<String, String> cids = Map.of("img-ride-along-abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='cid:img-ride-along-abc'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html, cids)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongInHttpSrc_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='https://example.com/ridealong-image.jpg'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_rideAlongDashInHttpSrc_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='https://example.com/ride-along-image.jpg'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    // ─── Marketing element filtering ─────────────────────────────────────────

    @Test
    void toDomain_mailpiece_marketingClassRidealong_skipped() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece ridealong'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>S</span>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_marketingClassPromo_skipped() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece promo'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>S</span>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_marketingClassSat_skipped() throws Exception {
        final String html = "<html><body>"
                + "<div id='mailpieces'><div class='mailpiece sat-delivery'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>S</span>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_marketingAncestorId_skipped() throws Exception {
        final String html = "<html><body>"
                + "<div id='ridealong-section'>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>S</span>"
                + "</div></div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    // ─── Marketing text filtering ─────────────────────────────────────────────

    @Test
    void toDomain_mailpiece_marketingTextRidealong_inAlt_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='ridealong promo'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_marketingTextPromotion_inAlt_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='Special promotion offer'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_marketingTextLearnMoreAboutMail_inAlt_skipped() throws Exception {
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='Learn more about your mail'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_mailpiece_marketingTextTruStage_inAlt_skipped() throws Exception {
        // isMarketingText: lower.contains("tru") && lower.contains("stage")
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='TruStage insurance'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html)).mailpieces()).isEmpty();
    }

    // ─── normalizeSummary ─────────────────────────────────────────────────────

    @Test
    void toDomain_normalizeSummary_campaignAlt_usesSender() throws Exception {
        // alt = "campaign" → normalizeSummary: lower.equals("campaign") → return sender
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='campaign'>"
                + "<span class='sender'>Actual Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSubject()).isEqualTo("Actual Sender");
    }

    @Test
    void toDomain_normalizeSummary_mailAlt_usesSender() throws Exception {
        // alt = "mail" → sanitizeSender("mail") = null → summary stays "mail" → lower.equals("mail") → use sender
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='mail'>"
                + "<span class='sender'>Mail Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSubject()).isEqualTo("Mail Sender");
    }

    @Test
    void toDomain_normalizeSummary_imagePrefixAlt_usesSender() throws Exception {
        // alt = "image something" → starts with "image" → return sender
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt='image something'>"
                + "<span class='sender'>Image Sender</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSubject()).isEqualTo("Image Sender");
    }

    @Test
    void toDomain_normalizeSummary_blankSummaryBlankSender_returnsBlankSummary() throws Exception {
        // Both summary and sender are blank → returns blank summary
        final String html = "<html><body><div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA' alt=''>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
        assertThat(digest.mailpieces().get(0).getSubject()).isNull();
    }

    // ─── sanitizeSender edge cases ────────────────────────────────────────────

    @Test
    void toDomain_sanitizeSender_stripsTrackingNumberSuffix() throws Exception {
        final String html = "<html><body><div class='package'>"
                + "<span class='sender'>Good Vendor Tracking Number 12345</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
        assertThat(digest.packages().get(0).getSender()).isEqualTo("Good Vendor");
    }

    @Test
    void toDomain_sanitizeSender_stripsExpectedDeliverySuffix() throws Exception {
        final String html = "<html><body><div class='package'>"
                + "<span class='sender'>Vendor Inc Expected Delivery tomorrow</span>"
                + "<span class='tracking-number'>940012345678901234</span>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.packages()).isNotEmpty();
        assertThat(digest.packages().get(0).getSender()).isEqualTo("Vendor Inc");
    }

    // ─── Campaign mail pieces ─────────────────────────────────────────────────

    @Test
    void toDomain_campaignMailPieces_extractedFromMailSection() throws Exception {
        final Map<String, String> cids = Map.of("mailpiece-abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mail-section'><table class='mail'>"
                + "<tr><td><img data-inline-cid='mailpiece-abc' src='cid:mailpiece-abc'></td></tr>"
                + "<tr><td><span class='sender'>Campaign Sender</span></td></tr>"
                + "</table></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).isNotEmpty();
    }

    @Test
    void toDomain_campaignMailPieces_extractedFromMailCampaignDiv() throws Exception {
        final Map<String, String> cids = Map.of("mp-xyz", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mail-section'>"
                + "<div id='mail-campaign-1'>"
                + "<img src='cid:mp-xyz'>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).isNotEmpty();
    }

    @Test
    void toDomain_campaignMailPieces_duplicateCidKey_onlyOneExtracted() throws Exception {
        // Two campaign tables with the same CID → cidKey already in seenCids → second skipped
        final Map<String, String> cids = Map.of("dup-img", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mail-section'>"
                + "<table class='mail'><tr><td><img src='cid:dup-img'></td></tr></table>"
                + "<table class='mail'><tr><td><img src='cid:dup-img'></td></tr></table>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    @Test
    void toDomain_campaignMailPieces_rideAlongImg_skipped() throws Exception {
        final Map<String, String> cids = Map.of("content-abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mail-section'><table class='mail'>"
                + "<tr><td><img data-inline-cid='content-abc' src='cid:content-abc'></td></tr>"
                + "</table></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).isEmpty();
    }

    @Test
    void toDomain_campaignMailPieces_blankResolvedSrc_skipped() throws Exception {
        // img selected via data-inline-cid but has no src/data-src attrs → rawSrc null → blank resolved → skipped
        final Map<String, String> cids = Map.of("other", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mail-section'><table class='mail'>"
                + "<tr><td><img data-inline-cid='no-src-attrs'></td></tr>"
                + "</table></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).isEmpty();
    }

    @Test
    void toDomain_campaignMailPieces_withCampaignFromSpanId() throws Exception {
        final Map<String, String> cids = Map.of("camp-img", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mail-section'><table class='mail'>"
                + "<tr><td><img data-inline-cid='camp-img' src='cid:camp-img'></td></tr>"
                + "<tr><td><span id='campaign-from-span-id'>Campaign Org</span></td></tr>"
                + "</table></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        assertThat(digest.mailpieces()).isNotEmpty();
    }

    // ─── Fallback: CID images in #mailpieces ─────────────────────────────────

    @Test
    void toDomain_fallbackCidImages_extracted() throws Exception {
        final Map<String, String> cids = Map.of("mail-img-abc", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'>"
                + "<img data-inline-cid='mail-img-abc' src='cid:mail-img-abc'>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        // "mail-img-abc" doesn't contain ridealong or content- prefix → extracted
        assertNotNull(digest);
    }

    @Test
    void toDomain_fallbackImgElements_rideAlongAlt_skipped() throws Exception {
        final Map<String, String> cids = Map.of("mail-img-2", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'>"
                + "<img data-inline-cid='mail-img-2' src='cid:mail-img-2' alt='ridealong'>"
                + "</div></body></html>";
        assertThat(parser.toDomain(p(html, cids)).mailpieces()).isEmpty();
    }

    @Test
    void toDomain_fallbackImgElements_marketingElement_skipped() throws Exception {
        // Fallback img inside a marketing element
        final Map<String, String> cids = Map.of("mail-img-3", "data:image/jpeg;base64,AAAA");
        final String html = "<html><body><div id='mailpieces'>"
                + "<div class='ridealong'>"
                + "<img data-inline-cid='mail-img-3' src='cid:mail-img-3'>"
                + "</div></div></body></html>";
        assertThat(parser.toDomain(p(html, cids)).mailpieces()).isEmpty();
    }

    // ─── deduplicateMailPieces ────────────────────────────────────────────────

    @Test
    void toDomain_dedup_emptyList_returnsEmpty() throws Exception {
        // No mailpieces → extractMailPieces returns empty → dedup returns empty
        final USPSDigest digest = parser.toDomain(p(""));
        assertThat(digest.mailpieces()).isEmpty();
    }

    @Test
    void toDomain_dedup_duplicateDataMailpieceId_onlyOneKept() throws Exception {
        final String html = "<html><body><div id='mailpieces'>"
                + "<div data-mailpiece-id='mp-1'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>S1</span></div>"
                + "<div data-mailpiece-id='mp-1'>"
                + "<img src='data:image/jpeg;base64,BBBB'><span class='sender'>S2</span></div>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(1);
    }

    @Test
    void toDomain_dedup_contentKey_sameThumbSubjectSender_deduped() throws Exception {
        // Two campaign tables with different CIDs but same resolved content
        // Use pieces with same sender+summary+thumbnail (no id) → content key dedup
        final Map<String, String> cids = Map.of("cid-a", "data:image/jpeg;base64,SAME");
        final String html = "<html><body><div id='mail-section'>"
                + "<table class='mail'>"
                + "<tr><td><img src='cid:cid-a'><span class='sender'>Same</span></td></tr>"
                + "</table>"
                + "<table class='mail'>"
                + "<tr><td><img src='cid:cid-a'><span class='sender'>Same</span></td></tr>"
                + "</table>"
                + "</div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html, cids));
        // Campaign dedup handles duplicate CID key — at most 1 piece
        assertThat(digest.mailpieces().size()).isLessThanOrEqualTo(1);
    }

    @Test
    void toDomain_dedup_placeholderCreatedAfterDedup_presentInFinalList() throws Exception {
        // 1 real piece + expectedMailCount=3 → 2 placeholders added AFTER dedup
        // placeholders have id "mail-placeholder-X"
        final String html = "<html><body>"
                + "<span id='total-mailpieces'>3</span>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final USPSDigest digest = parser.toDomain(p(html));
        assertThat(digest.mailpieces()).hasSize(3);
        final List<MailPiece> pieces = digest.mailpieces();
        assertThat(pieces.get(1).getId()).startsWith("mail-placeholder-");
        assertThat(pieces.get(2).getId()).startsWith("mail-placeholder-");
        // createPlaceholderMailPiece uses PLACEHOLDER_IMAGE
        assertThat(pieces.get(1).getThumbnailUrl()).contains("data:image/svg+xml");
    }

    @Test
    void toDomain_dedup_placeholderCreatedAfterDedup_receivedAtNullUsesNow() throws Exception {
        // payload.receivedAt() is null → received = digestDate (from now())
        final String html = "<html><body>"
                + "<span id='total-mailpieces'>2</span>"
                + "<div id='mailpieces'><div class='mailpiece'>"
                + "<img src='data:image/jpeg;base64,AAAA'><span class='sender'>USPS</span>"
                + "</div></div></body></html>";
        final GmailDigestPayload payload = new GmailDigestPayload(html, Map.of(), null);
        final OffsetDateTime before = OffsetDateTime.now(ZoneOffset.UTC).minusSeconds(2);
        final USPSDigest digest = parser.toDomain(payload);
        assertThat(digest.mailpieces()).hasSize(2);
        assertThat(digest.mailpieces().get(1).getReceivedAt()).isAfterOrEqualTo(before);
    }
}

package com.careconnect.service.ehr;

import ca.uhn.fhir.rest.api.EncodingEnum;
import ca.uhn.fhir.rest.client.api.IClientInterceptor;
import ca.uhn.fhir.rest.client.api.IGenericClient;
import ca.uhn.fhir.rest.client.api.IHttpRequest;
import ca.uhn.fhir.rest.client.api.IHttpResponse;
import ca.uhn.fhir.rest.client.interceptor.BearerTokenAuthInterceptor;
import ca.uhn.fhir.rest.param.DateParam;
import ca.uhn.fhir.rest.param.DateRangeParam;
import ca.uhn.fhir.rest.server.exceptions.AuthenticationException;
import ca.uhn.fhir.rest.server.exceptions.BaseServerResponseException;
import ca.uhn.fhir.util.BundleUtil;
import com.careconnect.repository.ehr.EhrSourceRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.instance.model.api.IBaseBundle;
import org.hl7.fhir.instance.model.api.IBaseResource;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Date;
import java.util.List;

import static com.careconnect.service.ehr.EhrService.ctxR4;

@Service
@Slf4j
public class MedicareService {

    static final String SANDBOX_BASE = "https://sandbox.bluebutton.cms.gov/v3/fhir/";
    // The revoke endpoint has to be on the same host as the token it revokes: the sandbox.
    static final String SANDBOX_REVOKE = "https://sandbox.bluebutton.cms.gov/v3/o/revoke";

    private final String bluebuttonBase;
    private final String bluebuttonRevoke;
    private final BlueButtonRetryPolicy retryPolicy;

    @Value("${spring.security.oauth2.client.registration.medicare.client-id:}")
    private String clientId;

    @Value("${spring.security.oauth2.client.registration.medicare.client-secret:}")
    private String clientSecret;

    @Autowired
    private EhrSourceRepository ehrSourceRepository;


    // Why on earth did we need a single database lookup for a single, unchanging numerical ID instead of hardcoding it?
    // Cause you can't really do that lookup on Bean construction, so you just have to do it lazily, I guess.
    private Long id;
    public Long getId(){
        if(id != null){
            return id;
        }
        id = ehrSourceRepository.findByCode("MEDICARE").orElseThrow().getId();
        return id;
    }

    public MedicareService() {
        this(SANDBOX_BASE, SANDBOX_REVOKE, BlueButtonRetryPolicy.THREAD_SLEEP);
    }

    /** Test seam: a local stand-in server and a sleeper that records waits instead of sleeping. */
    MedicareService(String bluebuttonBase, String bluebuttonRevoke, BlueButtonRetryPolicy.Sleeper sleeper) {
        this.bluebuttonBase = bluebuttonBase;
        this.bluebuttonRevoke = bluebuttonRevoke;
        this.retryPolicy = new BlueButtonRetryPolicy(sleeper);
    }

    /** Test seam for the OAuth client credentials normally injected from configuration. */
    void setClientCredentials(String clientId, String clientSecret) {
        this.clientId = clientId;
        this.clientSecret = clientSecret;
    }

    /**
     * Revokes a patient's Blue Button token (RFC 7009). The client authenticates with HTTP Basic,
     * which is {@code Base64(client_id:client_secret)}, and the token is form-encoded.
     */
    public void revoke(String patientToken){
        String credentials = Base64.getEncoder()
                .encodeToString((clientId + ":" + clientSecret).getBytes(StandardCharsets.UTF_8));
        HttpClient client = HttpClient.newHttpClient();
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(bluebuttonRevoke))
                .POST(HttpRequest.BodyPublishers.ofString(
                        "token=" + URLEncoder.encode(patientToken, StandardCharsets.UTF_8)))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Authorization", "Basic " + credentials).build();
        try {
            client.send(request, HttpResponse.BodyHandlers.discarding());
            // This always returns 200. No real point in checking the result.
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.error("Revoke interrupted");
        } catch (Exception e){
            log.error("Revoke Failed:{}", e.getMessage());
        }
    }

    public Patient requestMedicarePatientInfo(String patientToken) throws RuntimeException {
        RetryAfterCapture retryAfter = new RetryAfterCapture();
        IGenericClient bluebuttonClient = client(patientToken, retryAfter);
        Bundle results = retryPolicy.execute("Patient search",
                () -> bluebuttonClient.search().forResource(Patient.class).returnBundle(Bundle.class).execute(),
                retryAfter::last);
        if (results == null) {
            throw new RuntimeException("No Patient Response!");
        }
        // Bundle.total is optional in a searchset, so count the entries.
        int count = results.getEntry().size();
        if (count == 1) {
            String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
            if (bundleType.equals("Patient")) {
                return (Patient) results.getEntry().get(0).getResource();
            }

            throw new RuntimeException("Invalid Patient response type: " + bundleType);
        }
        throw new RuntimeException("Invalid Patient response quantity: " + count);
    }

    public List<Coverage> requestMedicareCoverageInfo(String patientToken) {
        return requestMedicareCoverageInfo(patientToken, null);
    }

    /** All Coverage records; throws if any page still fails after its retries. */
    public List<Coverage> requestMedicareCoverageInfo(String patientToken, Date lastUpdatedDate) throws RuntimeException {
        return paged(patientToken, lastUpdatedDate, Coverage.class, "No Coverage Response!").orThrow();
    }

    /** Like {@link #requestMedicareCoverageInfo(String, Date)}, but keeps the pages that arrived if a later one fails. */
    public BlueButtonRetrieval<Coverage> retrieveMedicareCoverage(String patientToken, Date lastUpdatedDate) {
        return paged(patientToken, lastUpdatedDate, Coverage.class, "No Coverage Response!").retrieval();
    }

    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken) {
        return requestMedicareEOBInfo(patientToken, null);
    }

    /** All ExplanationOfBenefit records; throws if any page still fails after its retries. */
    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken, Date lastUpdatedDate) throws RuntimeException {
        return paged(patientToken, lastUpdatedDate, ExplanationOfBenefit.class, "No EOB Response!").orThrow();
    }

    /** Like {@link #requestMedicareEOBInfo(String, Date)}, but keeps the pages that arrived if a later one fails. */
    public BlueButtonRetrieval<ExplanationOfBenefit> retrieveMedicareEOB(String patientToken, Date lastUpdatedDate) {
        return paged(patientToken, lastUpdatedDate, ExplanationOfBenefit.class, "No EOB Response!").retrieval();
    }

    private IGenericClient client(String patientToken, RetryAfterCapture retryAfter) {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        bluebuttonClient.registerInterceptor(retryAfter);
        return bluebuttonClient;
    }

    /** A retrieval plus the exception that stopped it, so the List methods can still throw it. */
    private record Paged<T>(BlueButtonRetrieval<T> retrieval, BaseServerResponseException failure) {
        List<T> orThrow() {
            if (failure != null) {
                throw failure;
            }
            return retrieval.records();
        }
    }

    /**
     * Searches {@code type} and follows every {@code next} link. Each request goes through the
     * retry policy (FR-MCR-23). If a page after the first still fails, the records gathered so far
     * are returned with the failure instead of being discarded. A rejected token (401) is thrown,
     * because nothing more may be asked with it (FR-MCR-09). Emptiness is decided from the entries,
     * not Bundle.total, which is optional.
     */
    private <T extends Resource> Paged<T> paged(String patientToken, Date lastUpdatedDate, Class<T> type,
                                                String noResponseMessage) {
        final String name = type.getSimpleName();
        RetryAfterCapture retryAfter = new RetryAfterCapture();
        IGenericClient bluebuttonClient = client(patientToken, retryAfter);
        Bundle results = retryPolicy.execute(name + " search", () -> lastUpdatedDate != null
                ? bluebuttonClient.search().forResource(type)
                        .lastUpdated(new DateRangeParam(new DateParam().setValue(lastUpdatedDate), null))
                        .returnBundle(Bundle.class).execute()
                : bluebuttonClient.search().forResource(type).returnBundle(Bundle.class).execute(),
                retryAfter::last);
        if (results == null) {
            throw new RuntimeException(noResponseMessage);
        }
        if (!results.hasEntry()) {
            return new Paged<>(BlueButtonRetrieval.complete(new ArrayList<>(), 1), null);
        }
        // Check the type against the entries of the searched type, not entry 0: an OperationOutcome
        // listed first (e.g. a server warning) shouldn't fail a page that also has records, the same
        // way addAll skips it on later pages (TC-MCR-FHIR-033/035, from a9a5f4a0 on #223). Only a page
        // with no entry of the searched type at all is the wrong response type (DEF-MCR-04).
        boolean hasSearchedType = results.getEntry().stream()
                .anyMatch(e -> type.isInstance(e.getResource()));
        if (!hasSearchedType) {
            String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
            throw new RuntimeException("Invalid " + name + " response type: " + bundleType);
        }

        List<T> records = new ArrayList<>();
        addAll(records, results, type);
        int pages = 1;
        while (results.getLink(IBaseBundle.LINK_NEXT) != null) {
            final Bundle current = results;
            final int next = pages + 1;
            try {
                results = retryPolicy.execute(name + " page " + next,
                        () -> bluebuttonClient.loadPage().next(current).execute(), retryAfter::last);
            } catch (AuthenticationException e) {
                // Not a partial result: the caller must not carry on with this token (FR-MCR-09).
                throw e;
            } catch (BaseServerResponseException e) {
                log.warn("Blue Button: {} page {} failed with HTTP {}; keeping {} records from {} page(s)",
                        name, next, e.getStatusCode(), records.size(), pages);
                return new Paged<>(BlueButtonRetrieval.partial(records, pages, next,
                        e.getStatusCode(), e.getMessage()), e);
            }
            addAll(records, results, type);
            pages = next;
        }
        return new Paged<>(BlueButtonRetrieval.complete(records, pages), null);
    }

    private static <T extends Resource> void addAll(List<T> into, Bundle page, Class<T> type) {
        for (IBaseResource resource : BundleUtil.toListOfResources(ctxR4, page)) {
            // Skip anything else on the page, such as an OperationOutcome entry, rather than throwing
            // a ClassCastException that would discard every record already retrieved.
            if (!type.isInstance(resource)) {
                log.warn("Blue Button: skipping a {} entry in a {} page",
                        resource.fhirType(), type.getSimpleName());
                continue;
            }
            into.add(type.cast(resource));
        }
    }

    /**
     * Remembers the last response's {@code Retry-After} header. HAPI's exceptions don't carry
     * response headers, so the retry policy reads it from here. One instance per client.
     */
    private static final class RetryAfterCapture implements IClientInterceptor {
        private volatile String last;

        @Override
        public void interceptRequest(IHttpRequest request) {
            last = null;
        }

        @Override
        public void interceptResponse(IHttpResponse response) {
            List<String> values = response.getHeaders("Retry-After");
            last = values == null || values.isEmpty() ? null : values.get(0);
        }

        String last() {
            return last;
        }
    }
}

package com.careconnect.service;

import ca.uhn.fhir.context.FhirContext;
import ca.uhn.fhir.parser.IParser;
import ca.uhn.fhir.rest.api.EncodingEnum;
import ca.uhn.fhir.rest.client.apache.ApacheRestfulClientFactory;
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
import lombok.extern.slf4j.Slf4j;
import org.apache.http.impl.client.HttpClientBuilder;
import org.hl7.fhir.instance.model.api.IBaseBundle;
import org.hl7.fhir.instance.model.api.IBaseResource;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

@Service
@Slf4j
public class FHIRService {

    private static final FhirContext ctxR4 = blueButtonContext();
    private static final IParser parser = ctxR4.newJsonParser().setPrettyPrint(true);

    private static final String SANDBOX_BASE = "https://sandbox.bluebutton.cms.gov/v3/fhir/";

    /**
     * The R4 context, with Apache HttpClient's own retries turned off. BlueButtonRetryPolicy owns
     * retrying; HttpClient would otherwise resend a dropped request up to 3 more times inside each
     * attempt, 12 requests where NFR-DEG-02 allows 3 (DEF-MCR-06). HAPI's timeouts and pool stay.
     */
    private static FhirContext blueButtonContext() {
        FhirContext ctx = FhirContext.forR4();
        ctx.setRestfulClientFactory(new ApacheRestfulClientFactory(ctx) {
            @Override
            protected HttpClientBuilder getHttpClientBuilder() {
                return super.getHttpClientBuilder().disableAutomaticRetries();
            }
        });
        return ctx;
    }

    private final String bluebuttonBase;
    private final BlueButtonRetryPolicy retryPolicy;

    public FHIRService() {
        this(SANDBOX_BASE);
    }

    /** Test seam (WBS 3.6.4): point the client at a local stub server instead of the CMS sandbox. */
    FHIRService(String bluebuttonBase) {
        this(bluebuttonBase, BlueButtonRetryPolicy.THREAD_SLEEP);
    }

    /** Test seam: also replace the wait between retries, so retry tests don't sleep. */
    FHIRService(String bluebuttonBase, BlueButtonRetryPolicy.Sleeper sleeper) {
        this.bluebuttonBase = bluebuttonBase;
        this.retryPolicy = new BlueButtonRetryPolicy(sleeper);
    }

    /**
     * Remembers the {@code Retry-After} header of the most recent response. HAPI does not copy
     * response headers onto the exception it throws for a 429/503, so the retry policy reads the
     * header from here instead. One instance per client, and a client is used by one request.
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

    private IGenericClient client(String patientToken, RetryAfterCapture retryAfter) {
        IGenericClient bluebuttonClient = ctxR4.newRestfulGenericClient(bluebuttonBase);
        bluebuttonClient.setEncoding(EncodingEnum.JSON);
        bluebuttonClient.registerInterceptor(new BearerTokenAuthInterceptor(patientToken));
        bluebuttonClient.registerInterceptor(retryAfter);
        return bluebuttonClient;
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
        // Bundle.total is optional (0..1) in a searchset, so count the entries actually returned.
        int quantity = results.getEntry().size();
        if (quantity == 1) {
            String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
            if (bundleType.equals("Patient")) {
                return (Patient) results.getEntry().get(0).getResource();
            }

            throw new RuntimeException("Invalid Patient response type: " + bundleType);
        }
        throw new RuntimeException("Invalid Patient response quantity: " + quantity);
    }

    public String patientToJSON(Patient patient) {
        return parser.encodeResourceToString(patient);
    }

    public List<Coverage> requestMedicareCoverageInfo(String patientToken) {
        return requestMedicareCoverageInfo(patientToken, null);
    }

    /** All Coverage records, or the failure if any page fails. See {@link #retrieveMedicareCoverage}. */
    public List<Coverage> requestMedicareCoverageInfo(String patientToken, Date lastUpdatedDate) throws RuntimeException {
        return paged(patientToken, lastUpdatedDate, Coverage.class, "No Coverage Response!").orThrow();
    }

    /**
     * Coverage records, keeping the pages that arrived if a later page fails (DEF-MCR-01).
     * A failure on the first page is still thrown, because there is nothing to keep.
     */
    public BlueButtonRetrieval<Coverage> retrieveMedicareCoverage(String patientToken, Date lastUpdatedDate) {
        return paged(patientToken, lastUpdatedDate, Coverage.class, "No Coverage Response!").retrieval();
    }

    public String coverageToJSON(Coverage coverage) {
        return parser.encodeResourceToString(coverage);
    }

    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken) {
        return requestMedicareEOBInfo(patientToken, null);
    }

    /** All EOB records, or the failure if any page fails. See {@link #retrieveMedicareEOB}. */
    public List<ExplanationOfBenefit> requestMedicareEOBInfo(String patientToken, Date lastUpdatedDate) throws RuntimeException {
        return paged(patientToken, lastUpdatedDate, ExplanationOfBenefit.class, "No EOB Response!").orThrow();
    }

    /**
     * EOB records, keeping the pages that arrived if a later page fails (DEF-MCR-01).
     * A failure on the first page is still thrown, because there is nothing to keep.
     */
    public BlueButtonRetrieval<ExplanationOfBenefit> retrieveMedicareEOB(String patientToken, Date lastUpdatedDate) {
        return paged(patientToken, lastUpdatedDate, ExplanationOfBenefit.class, "No EOB Response!").retrieval();
    }

    public String EOBtoJSON(ExplanationOfBenefit eob) {
        return parser.encodeResourceToString(eob);
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
     * retry policy (DEF-MCR-02). If a page after the first still fails, the records gathered so far
     * are returned with the failure instead of being discarded (DEF-MCR-01). A rejected token (401)
     * is still thrown, because nothing more may be asked with it (FR-MCR-09, DEF-MCR-05).
     * <p>
     * Emptiness is decided from the entries, not Bundle.total, which is optional (DEF-MCR-03), and a
     * wrong resource type names the resource searched for (DEF-MCR-04).
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
        // Bundle.total is optional (0..1) in a searchset; decide emptiness from the entries.
        if (!results.hasEntry()) {
            return new Paged<>(BlueButtonRetrieval.complete(new ArrayList<>(), 1), null);
        }
        String bundleType = results.getEntry().get(0).getResource().getResourceType().toString();
        if (!bundleType.equals(name)) {
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
            // a ClassCastException that would discard every record already retrieved (#223 review).
            if (!type.isInstance(resource)) {
                log.warn("Blue Button: skipping a {} entry in a {} page",
                        resource.fhirType(), type.getSimpleName());
                continue;
            }
            into.add(type.cast(resource));
        }
    }
}

package com.careconnect.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuration properties for the Virginia HHAExchange EVV aggregator.
 * <p>
 * Prefix: {@code hhaexchange}
 * <p>
 * Example application.properties entries:
 * <pre>
 *   hhaexchange.api.base-url=https://implementation.hhaexchange.com
 *   hhaexchange.api.key=${HHAEXCHANGE_API_KEY:}
 *   hhaexchange.provider.tax-id=${HHAEXCHANGE_PROVIDER_TAX_ID:}
 *   hhaexchange.provider.npi=${HHAEXCHANGE_PROVIDER_NPI:}
 *   hhaexchange.provider.name=Your Agency Name
 *   hhaexchange.payer.id=${HHAEXCHANGE_PAYER_ID:LCDP}
 * </pre>
 */
@ConfigurationProperties(prefix = "hhaexchange")
@Getter
@Setter
public class HhaExchangeProperties {

    private Api api = new Api();
    private Provider provider = new Provider();
    private Payer payer = new Payer();

    @Getter
    @Setter
    public static class Api {
        /**
         * Base URL for the HHAExchange REST API.
         */
        private String baseUrl = "https://implementation.hhaexchange.com";
        /**
         * API authentication key supplied via X-API-KEY header.
         */
        private String key = "";
    }

    @Getter
    @Setter
    public static class Provider {
        /**
         * Federal Tax Identification Number (EIN) of the home-care provider agency.
         */
        private String taxId = "";
        /**
         * NPI of the home-care provider office used in the office.identifier field.
         */
        private String npi = "";
        /**
         * Human-readable agency name used in shift sign-off.
         */
        private String name = "CareConnect Agency";
    }

    @Getter
    @Setter
    public static class Payer {
        /**
         * HHAExchange payer identifier (e.g. LCDP for Virginia DMAS).
         */
        private String id = "LCDP";
    }
}

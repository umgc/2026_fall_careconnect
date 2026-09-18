package com.careconnect.service;

import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.Map;

/**
 * Tax calculation service for subscription billing.
 * Currently uses hardcoded state tax rates (simplified MVP).
 * In production, integrate with Stripe Tax, Avalara, or TaxJar.
 */
@Service
public class TaxCalculationService {

    // State tax rates (sales tax) - simplified, does not account for local taxes
    // Source: typical US state sales tax rates as of 2026
    private static final Map<String, Double> STATE_TAX_RATES = new HashMap<>();

    static {
        STATE_TAX_RATES.put("AL", 0.04);  // 4%
        STATE_TAX_RATES.put("AK", 0.0);   // 0% (no state sales tax)
        STATE_TAX_RATES.put("AZ", 0.0598); // 5.98%
        STATE_TAX_RATES.put("AR", 0.065);  // 6.5%
        STATE_TAX_RATES.put("CA", 0.0725); // 7.25%
        STATE_TAX_RATES.put("CO", 0.029);  // 2.9%
        STATE_TAX_RATES.put("CT", 0.0635); // 6.35%
        STATE_TAX_RATES.put("DE", 0.0);    // 0% (no state sales tax)
        STATE_TAX_RATES.put("FL", 0.06);   // 6%
        STATE_TAX_RATES.put("GA", 0.04);   // 4%
        STATE_TAX_RATES.put("HI", 0.04);   // 4%
        STATE_TAX_RATES.put("ID", 0.06);   // 6%
        STATE_TAX_RATES.put("IL", 0.0625); // 6.25%
        STATE_TAX_RATES.put("IN", 0.07);   // 7%
        STATE_TAX_RATES.put("IA", 0.06);   // 6%
        STATE_TAX_RATES.put("KS", 0.065);  // 6.5%
        STATE_TAX_RATES.put("KY", 0.06);   // 6%
        STATE_TAX_RATES.put("LA", 0.045);  // 4.5%
        STATE_TAX_RATES.put("ME", 0.055);  // 5.5%
        STATE_TAX_RATES.put("MD", 0.06);   // 6%
        STATE_TAX_RATES.put("MA", 0.0625); // 6.25%
        STATE_TAX_RATES.put("MI", 0.06);   // 6%
        STATE_TAX_RATES.put("MN", 0.065);  // 6.5%
        STATE_TAX_RATES.put("MS", 0.07);   // 7%
        STATE_TAX_RATES.put("MO", 0.0423); // 4.23%
        STATE_TAX_RATES.put("MT", 0.0);    // 0% (no state sales tax)
        STATE_TAX_RATES.put("NE", 0.055);  // 5.5%
        STATE_TAX_RATES.put("NV", 0.0685); // 6.85%
        STATE_TAX_RATES.put("NH", 0.0);    // 0% (no state sales tax)
        STATE_TAX_RATES.put("NJ", 0.0625); // 6.25%
        STATE_TAX_RATES.put("NM", 0.05);   // 5%
        STATE_TAX_RATES.put("NY", 0.04);   // 4% (plus local, typical ~8%)
        STATE_TAX_RATES.put("NC", 0.0475); // 4.75%
        STATE_TAX_RATES.put("ND", 0.05);   // 5%
        STATE_TAX_RATES.put("OH", 0.0575); // 5.75%
        STATE_TAX_RATES.put("OK", 0.0450); // 4.5%
        STATE_TAX_RATES.put("OR", 0.0);    // 0% (no state sales tax)
        STATE_TAX_RATES.put("PA", 0.06);   // 6%
        STATE_TAX_RATES.put("RI", 0.07);   // 7%
        STATE_TAX_RATES.put("SC", 0.07);   // 7%
        STATE_TAX_RATES.put("SD", 0.045);  // 4.5%
        STATE_TAX_RATES.put("TN", 0.0955); // 9.55%
        STATE_TAX_RATES.put("TX", 0.0625); // 6.25%
        STATE_TAX_RATES.put("UT", 0.0595); // 5.95%
        STATE_TAX_RATES.put("VT", 0.06);   // 6%
        STATE_TAX_RATES.put("VA", 0.043);  // 4.3%
        STATE_TAX_RATES.put("WA", 0.065);  // 6.5%
        STATE_TAX_RATES.put("WV", 0.06);   // 6%
        STATE_TAX_RATES.put("WI", 0.05);   // 5%
        STATE_TAX_RATES.put("WY", 0.04);   // 4%
        STATE_TAX_RATES.put("DC", 0.06);   // 6%
    }

    /**
     * Get tax rate for a given state
     *
     * @param state 2-letter state code
     * @return tax rate as decimal (e.g., 0.0725 for 7.25%), or 0.0 if not found
     */
    public Double getTaxRateByState(String state) {
        if (state == null || state.trim().isEmpty()) {
            return 0.0;
        }
        return STATE_TAX_RATES.getOrDefault(state.toUpperCase(), 0.0);
    }

    /**
     * Calculate tax amount in cents
     *
     * @param subtotalCents subtotal in cents
     * @param taxRate       tax rate as decimal (e.g., 0.0725)
     * @return tax amount in cents (rounded down)
     */
    public Long calculateTaxCents(Long subtotalCents, Double taxRate) {
        if (subtotalCents == null || subtotalCents <= 0 || taxRate == null || taxRate <= 0) {
            return 0L;
        }
        return Math.round(subtotalCents * taxRate);
    }

    /**
     * Calculate complete billing breakdown
     *
     * @param subtotalCents subscription price in cents
     * @param state         2-letter state code
     * @return total in cents (subtotal + tax)
     */
    public Long calculateTotal(Long subtotalCents, String state) {
        if (subtotalCents == null || subtotalCents <= 0) {
            return 0L;
        }
        Double taxRate = getTaxRateByState(state);
        Long taxCents = calculateTaxCents(subtotalCents, taxRate);
        return subtotalCents + taxCents;
    }
}

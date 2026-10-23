package com.careconnect.model.emergency;

/**
 * The categories of information a patient can choose to show on their Emergency Care Passport
 * (CC-12). Visibility is opted into per category, never per item: a patient who makes
 * {@link #ALLERGIES} public shows every active allergy, not a chosen subset.
 * <p>
 * {@link #ALLERGIES} and {@link #MEDICATIONS} read from the existing {@code patient_allergy} and
 * {@code patient_medication} tables (active rows only); the other three read from
 * {@code emergency_passport_profile}.
 */
public enum PassportField {
    ALLERGIES,
    MEDICATIONS,
    CHRONIC_CONDITIONS,
    BLOOD_TYPE,
    EMERGENCY_CONTACT
}

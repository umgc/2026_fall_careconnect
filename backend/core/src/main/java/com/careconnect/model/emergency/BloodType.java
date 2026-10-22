package com.careconnect.model.emergency;

/**
 * ABO/Rh blood group as the patient reports it. Stored by name, e.g. {@code O_NEGATIVE}.
 * <p>
 * There is no {@code UNKNOWN}: a patient who does not know their blood type leaves
 * {@code emergency_passport_profile.blood_type} null, so "not recorded" has one representation.
 */
public enum BloodType {
    A_POSITIVE,
    A_NEGATIVE,
    B_POSITIVE,
    B_NEGATIVE,
    AB_POSITIVE,
    AB_NEGATIVE,
    O_POSITIVE,
    O_NEGATIVE
}

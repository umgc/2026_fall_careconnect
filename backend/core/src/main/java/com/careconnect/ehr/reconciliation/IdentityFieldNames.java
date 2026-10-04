package com.careconnect.ehr.reconciliation;

import java.util.Set;

/**
 * The field names the reconciliation library understands — the keys of
 * {@link SourceIdentitySnapshot#fields()}, and the {@code field_name} values written to
 * {@code ehr_identity_conflict} and {@code ehr_identity_field_provenance}.
 *
 * <p>They are the {@code ehr_source_identity} column names, which follow FHIR ({@code given_name},
 * not {@code first_name}). Adapters should build their snapshot from these constants rather than
 * from string literals: a misspelt key is otherwise only caught at run time, when
 * {@code JpaPatientFieldAccessor} rejects it part-way through a snapshot (PR #216 review).
 *
 * <p>Deliberately not an enum. The library's interfaces take a {@code String} so an adapter on a
 * different persistence stack can implement them without depending on this class, and the audit
 * tables store the name as text.
 */
public final class IdentityFieldNames {

    public static final String GIVEN_NAME = "given_name";
    public static final String FAMILY_NAME = "family_name";
    /** The one field that can stay {@code PENDING} until the patient confirms it. */
    public static final String DATE_OF_BIRTH = "date_of_birth";
    public static final String PHONE = "phone";
    public static final String EMAIL = "email";
    public static final String ADDRESS_LINE1 = "address_line1";
    public static final String ADDRESS_LINE2 = "address_line2";
    public static final String CITY = "city";
    public static final String STATE = "state";
    public static final String POSTAL_CODE = "postal_code";

    /** Every name above. {@code member_id}, {@code gender}, {@code managing_org} and
     *  {@code language} are carried on {@code ehr_source_identity} but are not reconciled, so they
     *  are not here. */
    public static final Set<String> ALL = Set.of(
            GIVEN_NAME, FAMILY_NAME, DATE_OF_BIRTH, PHONE, EMAIL,
            ADDRESS_LINE1, ADDRESS_LINE2, CITY, STATE, POSTAL_CODE);

    private IdentityFieldNames() {
    }
}

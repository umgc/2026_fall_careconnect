package com.careconnect.service;

import com.careconnect.repository.FriendRequestRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("MessagingPolicy: who may message whom")
class MessagingPolicyTest {

    private static final Long CAREGIVER = 10L;
    private static final Long PATIENT = 20L;
    private static final Long STRANGER = 30L;

    @Mock
    private CaregiverPatientLinkService linkService;
    @Mock
    private FriendRequestRepository friendRequests;
    @InjectMocks
    private MessagingPolicy policy;

    @Test
    @DisplayName("a caregiver can message a linked patient when the link allows messaging")
    void caregiverToLinkedPatient_messagingOn_allowed() {
        when(linkService.hasAccessToPatient(CAREGIVER, PATIENT)).thenReturn(true);
        when(linkService.isPatientMessagingEnabled(CAREGIVER, PATIENT)).thenReturn(true);

        assertThat(policy.canMessage(CAREGIVER, PATIENT)).isTrue();
    }

    @Test
    @DisplayName("a patient can message their caregiver when the link allows messaging")
    void patientToCaregiver_messagingOn_allowed() {
        when(linkService.hasAccessToPatient(PATIENT, CAREGIVER)).thenReturn(false);
        when(linkService.hasAccessToPatient(CAREGIVER, PATIENT)).thenReturn(true);
        when(linkService.isPatientMessagingEnabled(CAREGIVER, PATIENT)).thenReturn(true);

        assertThat(policy.canMessage(PATIENT, CAREGIVER)).isTrue();
    }

    @Test
    @DisplayName("messaging turned off on the link blocks both directions")
    void linkWithMessagingOff_blocksBothDirections() {
        when(linkService.hasAccessToPatient(CAREGIVER, PATIENT)).thenReturn(true);
        when(linkService.isPatientMessagingEnabled(CAREGIVER, PATIENT)).thenReturn(false);

        assertThat(policy.canMessage(CAREGIVER, PATIENT)).isFalse();
        assertThat(policy.canMessage(PATIENT, CAREGIVER)).isFalse();
    }

    @Test
    @DisplayName("being friends does not get round a link with messaging off")
    void linkWithMessagingOff_friendshipIgnored() {
        when(linkService.hasAccessToPatient(CAREGIVER, PATIENT)).thenReturn(true);
        when(linkService.isPatientMessagingEnabled(CAREGIVER, PATIENT)).thenReturn(false);

        assertThat(policy.canMessage(CAREGIVER, PATIENT)).isFalse();
        verify(friendRequests, never()).existsAcceptedBetween(CAREGIVER, PATIENT);
    }

    @Test
    @DisplayName("two users with no link can message once a friend request between them was accepted")
    void noLink_friends_allowed() {
        when(friendRequests.existsAcceptedBetween(PATIENT, STRANGER)).thenReturn(true);

        assertThat(policy.canMessage(PATIENT, STRANGER)).isTrue();
    }

    @Test
    @DisplayName("two users with no link and no accepted friend request cannot message")
    void noLink_notFriends_refused() {
        when(friendRequests.existsAcceptedBetween(PATIENT, STRANGER)).thenReturn(false);

        assertThat(policy.canMessage(PATIENT, STRANGER)).isFalse();
    }

    @Test
    @DisplayName("a missing sender or receiver, or messaging yourself, is refused without a lookup")
    void nullOrSelf_refused() {
        assertThat(policy.canMessage(null, PATIENT)).isFalse();
        assertThat(policy.canMessage(PATIENT, null)).isFalse();
        assertThat(policy.canMessage(PATIENT, PATIENT)).isFalse();
        verifyNoInteractions(linkService, friendRequests);
    }
}

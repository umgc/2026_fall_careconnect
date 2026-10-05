// Unit tests for resolveTranscriptSpeakerLabel (hybrid_video_call_widget.dart).
//
// Regression coverage for the live-caption speaker-label bug: the backend's Chime
// externalUserId is an opaque, privacy-preserving UUID with no role embedded in it
// (ChimeService#toOpaqueChimeExternalUserId). A prior version of this widget tried to
// decode a role/name out of that UUID and displayed the raw id when decoding failed.
// resolveTranscriptSpeakerLabel instead uses roles the call already knows client-side
// (the local user's own role, and the other party's recipientRole) and never attempts
// to interpret the opaque id — it only compares it for equality to identify the local
// speaker.
//
// Pure-function unit tests (no widget pump) because HybridVideoCallWidget always fails
// to join in this test environment (no live backend/JWT — see
// test/video_call/hybrid_video_call_widget_test.dart's architecture note), so
// _callSession is never populated and the private instance method is unreachable via
// pumpWidget.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';

void main() {
  group('resolveTranscriptSpeakerLabel', () {
    test('empty speakerLabel falls back to the local caregiver role', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: '',
        localExternalUserId: 'local-uuid',
        localAttendeeId: 'local-attendee',
        isLocalPatientView: false,
        isLocalCaregiverView: true,
        recipientRole: 'PATIENT',
      );
      expect(label, 'CAREGIVER');
    });

    test('empty speakerLabel falls back to the local patient role', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: null,
        localExternalUserId: 'local-uuid',
        localAttendeeId: 'local-attendee',
        isLocalPatientView: true,
        isLocalCaregiverView: false,
        recipientRole: 'CAREGIVER',
      );
      expect(label, 'PATIENT');
    });

    test(
        'a sample whose speaker matches the local externalUserId is attributed '
        'to the local role, not decoded', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: '9c1f2b7a-3d44-3e21-8b0c-5f6a7d8e9012',
        localExternalUserId: '9c1f2b7a-3d44-3e21-8b0c-5f6a7d8e9012',
        localAttendeeId: 'some-other-attendee-id',
        isLocalPatientView: false,
        isLocalCaregiverView: true,
        recipientRole: 'PATIENT',
      );
      expect(label, 'CAREGIVER');
    });

    test(
        'a sample whose speaker matches the local attendeeId is attributed '
        'to the local role', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: 'attendee-abc-123',
        localExternalUserId: 'some-other-external-id',
        localAttendeeId: 'attendee-abc-123',
        isLocalPatientView: true,
        isLocalCaregiverView: false,
        recipientRole: 'CAREGIVER',
      );
      expect(label, 'PATIENT');
    });

    test(
        'a remote opaque UUID speaker is attributed to recipientRole, never '
        'displayed as the raw UUID', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: '5e2a9d10-77c4-4b1a-9f00-1234567890ab',
        localExternalUserId: '9c1f2b7a-3d44-3e21-8b0c-5f6a7d8e9012',
        localAttendeeId: 'local-attendee',
        isLocalPatientView: false,
        isLocalCaregiverView: true,
        recipientRole: 'PATIENT',
      );
      expect(label, 'PATIENT');
      expect(label, isNot(contains('-')));
    });

    test(
        'remote speaker with a missing/invalid recipientRole falls back to the '
        'opposite of the local role', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: 'remote-uuid',
        localExternalUserId: 'local-uuid',
        localAttendeeId: 'local-attendee',
        isLocalPatientView: false,
        isLocalCaregiverView: true,
        recipientRole: null,
      );
      expect(label, 'PATIENT');
    });

    test('local/remote id comparison is case-insensitive', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: 'LOCAL-UUID',
        localExternalUserId: 'local-uuid',
        localAttendeeId: null,
        isLocalPatientView: false,
        isLocalCaregiverView: true,
        recipientRole: 'PATIENT',
      );
      expect(label, 'CAREGIVER');
    });

    test('neither role known and no local match falls back to PARTICIPANT', () {
      final label = resolveTranscriptSpeakerLabel(
        rawSpeakerLabel: '',
        localExternalUserId: null,
        localAttendeeId: null,
        isLocalPatientView: false,
        isLocalCaregiverView: false,
        recipientRole: null,
      );
      expect(label, 'PARTICIPANT');
    });
  });
}

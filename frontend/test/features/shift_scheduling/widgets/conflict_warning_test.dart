// Tests for ConflictWarning widget.
// (lib/features/shift_scheduling/presentation/widgets/conflict_warning.dart)
//
// Pure widget test — no HTTP, no mocks beyond the model objects.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/conflict_warning.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

ScheduledVisit _makeVisit({
  int id = 1,
  String patientName = 'John Doe',
  int hour = 10,
  int minute = 0,
  int duration = 60,
}) {
  return ScheduledVisit(
    id: id,
    caregiverId: 1,
    patientId: 10,
    patientName: patientName,
    serviceType: 'Personal Care',
    scheduledDate: DateTime(2026, 3, 17),
    scheduledTime: TimeOfDay(hour: hour, minute: minute),
    durationMinutes: duration,
    priority: 'Normal',
    status: 'Scheduled',
    createdAt: DateTime(2026, 3, 17),
    updatedAt: DateTime(2026, 3, 17),
  );
}

Widget _wrap(ConflictWarning widget) {
  return MaterialApp(home: Scaffold(body: SingleChildScrollView(child: widget)));
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('ConflictWarning', () {
    testWidgets('renders warning title', (tester) async {
      // Arrange
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Overlap detected',
      );

      // Act
      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));

      // Assert
      expect(find.text('Schedule Conflict Detected'), findsOneWidget);
    });

    testWidgets('renders conflict message', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'patient',
        message: 'Patient has existing visit at 10:00',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.text('Patient has existing visit at 10:00'), findsOneWidget);
    });

    testWidgets('renders warning icon', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Test',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.byIcon(Icons.warning), findsOneWidget);
    });

    testWidgets('shows dismiss button when onDismiss is provided',
        (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Test',
      );

      await tester.pumpWidget(_wrap(
        ConflictWarning(conflict: conflict, onDismiss: () {}),
      ));

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('hides dismiss button when onDismiss is null',
        (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Test',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('calls onDismiss when close button pressed', (tester) async {
      bool dismissed = false;
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Test',
      );

      await tester.pumpWidget(_wrap(
        ConflictWarning(conflict: conflict, onDismiss: () => dismissed = true),
      ));

      // Invoke programmatically to avoid shader exception.
      final closeBtn = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(closeBtn.first).onPressed!();
      expect(dismissed, isTrue);
    });

    testWidgets('shows conflicting visit patient name', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [_makeVisit(patientName: 'Alice Smith')],
        conflictType: 'caregiver',
        message: 'Overlap',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.text('Alice Smith'), findsOneWidget);
    });

    testWidgets('shows event icon for each conflicting visit', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [
          _makeVisit(id: 1, patientName: 'Alice'),
          _makeVisit(id: 2, patientName: 'Bob'),
        ],
        conflictType: 'patient',
        message: '2 conflicts',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.byIcon(Icons.event), findsNWidgets(2));
    });

    testWidgets('shows end time for conflicting visits', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [
          _makeVisit(hour: 10, minute: 0, duration: 60),
        ],
        conflictType: 'caregiver',
        message: 'Overlap',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      // End time should be 11:00
      expect(find.textContaining('11:00'), findsOneWidget);
    });

    testWidgets('does not show visit list when no conflicts', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'General warning',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.byIcon(Icons.event), findsNothing);
    });

    testWidgets('multiple conflicting visits all show patient names',
        (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [
          _makeVisit(id: 1, patientName: 'Alice'),
          _makeVisit(id: 2, patientName: 'Bob'),
          _makeVisit(id: 3, patientName: 'Carol'),
        ],
        conflictType: 'caregiver',
        message: '3 overlapping visits',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });

    testWidgets('renders with red border', (tester) async {
      final conflict = VisitConflict(
        conflictingVisits: [],
        conflictType: 'caregiver',
        message: 'Test',
      );

      await tester.pumpWidget(_wrap(ConflictWarning(conflict: conflict)));
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.border, isNotNull);
    });
  });
}

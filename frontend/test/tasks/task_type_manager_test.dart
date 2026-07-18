import 'dart:convert';

import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaskTypeManager', () {
    late TaskTypeManager manager;

    setUp(() async {
      // Reset SharedPreferences mock before each test
      SharedPreferences.setMockInitialValues({});
      manager = TaskTypeManager();
      await Future.delayed(const Duration(milliseconds: 10));
    });

    test('loads default task types when no prefs exist', () async {
      final keys = manager.getSortedTypes();

      expect(keys, contains('medication'));
      expect(manager.getIcon('appointment'), Icons.event);
      //  Compare by value to avoid MaterialColor vs Color mismatch
      expect(manager.getColor('exercise').value, Colors.green.value);
    });

    test('addTaskType adds a new entry and persists it', () async {
      await manager.addTaskType(
        'hydration',
        Colors.blueGrey,
        icon: Icons.water_drop,
      );

      expect(manager.taskTypeColors.containsKey('hydration'), true);
      expect(manager.getIcon('hydration'), Icons.water_drop);
      expect(manager.getColor('hydration').value, Colors.blueGrey.value);

      //  Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('task_type_settings');
      expect(jsonStr, isNotNull);

      final decoded = json.decode(jsonStr!);
      expect(decoded.containsKey('hydration'), true);
    });

    test('removeTaskType removes and updates prefs', () async {
      await manager.addTaskType('test', Colors.cyan);
      expect(manager.taskTypeColors.containsKey('test'), true);

      await manager.removeTaskType('test');
      expect(manager.taskTypeColors.containsKey('test'), false);

      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('task_type_settings');
      final decoded = json.decode(jsonStr!);
      expect(decoded.containsKey('test'), false);
    });

    test('updateTaskColor changes color and persists it', () async {
      await manager.addTaskType('therapy', Colors.amber);
      expect(manager.getColor('therapy').value, Colors.amber.value);

      await manager.updateTaskColor('therapy', Colors.purple);
      expect(manager.getColor('therapy').value, Colors.purple.value);

      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('task_type_settings');
      final decoded = json.decode(jsonStr!);
      expect(decoded['therapy']['color'], Colors.purple.value);
    });

    test('updateTaskIcon changes icon and persists it', () async {
      await manager.addTaskType('monitoring', Colors.red);
      expect(manager.getIcon('monitoring'), Icons.task);

      await manager.updateTaskIcon('monitoring', Icons.science);
      expect(manager.getIcon('monitoring'), Icons.science);

      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('task_type_settings');
      final decoded = json.decode(jsonStr!);
      expect(decoded['monitoring']['icon'], 'science');
    });

    test('resetDefaults restores all predefined types', () async {
      await manager.addTaskType('custom', Colors.black);
      expect(manager.taskTypeColors.containsKey('custom'), true);

      await manager.resetDefaults();
      expect(manager.taskTypeColors.containsKey('custom'), false);
      expect(manager.taskTypeColors.containsKey('medication'), true);
    });

    test('getColor and getIcon return fallback for unknown types', () async {
      expect(manager.getColor('unknown').value, Colors.deepOrange.value);
      expect(manager.getIcon('unknown'), Icons.task);
    });

    test('getSortedTypes returns sorted list', () async {
      await manager.addTaskType('Zeta', Colors.purple);
      await manager.addTaskType('Alpha', Colors.red);

      final sorted = manager.getSortedTypes();
      expect(sorted.first, 'alpha');
      expect(sorted.last, 'zeta');
    });

    test(
      'persistence works: data is reloaded from SharedPreferences',
      () async {
        // Simulate stored data in prefs
        final prefs = await SharedPreferences.getInstance();
        final encoded = json.encode({
          'hydration': {
            'color': Colors.blue.toARGB32(),
            'icon': 'science',
          },
        });
        await prefs.setString('task_type_settings', encoded);

        // Create a new manager → should auto-load hydration
        final manager2 = TaskTypeManager();
        await Future.delayed(const Duration(milliseconds: 10));

        //  Compare by color value
        expect(manager2.getColor('hydration').toARGB32(), Colors.blue.toARGB32());
        expect(manager2.getIcon('hydration'), Icons.science);
      },
    );

    // getColor and getIcon should return fallback values when passed null
    test('getColor returns deepOrange for null type', () async {
      expect(manager.getColor(null).toARGB32(), Colors.deepOrange.toARGB32());
    });

    test('getIcon returns Icons.task for null type', () async {
      expect(manager.getIcon(null), Icons.task);
    });

    // addTaskType without an explicit icon should default to Icons.task
    test('addTaskType without icon defaults to Icons.task', () async {
      await manager.addTaskType('sleep', Colors.indigo);
      expect(manager.getIcon('sleep'), Icons.task);
    });

    // Names should be normalised to lowercase on storage and lookup
    test('addTaskType stores type name in lowercase', () async {
      await manager.addTaskType('NUTRITION', Colors.lime, icon: Icons.restaurant);
      // The key must be lower-cased
      expect(manager.taskTypeColors.containsKey('nutrition'), isTrue);
      expect(manager.taskTypeColors.containsKey('NUTRITION'), isFalse);
    });

    test('getColor is case-insensitive for type lookup', () async {
      await manager.addTaskType('SLEEP', Colors.indigo);
      // Look up with different casing
      expect(manager.getColor('sleep').toARGB32(), Colors.indigo.toARGB32());
      expect(manager.getColor('SLEEP').toARGB32(), Colors.indigo.toARGB32());
    });

    test('getIcon is case-insensitive for type lookup', () async {
      await manager.addTaskType('SLEEP', Colors.indigo, icon: Icons.bedtime);
      expect(manager.getIcon('Sleep'), Icons.bedtime);
    });

    // updateTaskColor on a non-existent key should be a silent no-op
    test('updateTaskColor on non-existent key does nothing', () async {
      // Should complete without throwing and leave existing state unchanged
      await expectLater(
        manager.updateTaskColor('nonexistent', Colors.red),
        completes,
      );
      expect(manager.taskTypeColors.containsKey('nonexistent'), isFalse);
    });

    // updateTaskIcon on a non-existent key should be a silent no-op
    test('updateTaskIcon on non-existent key does nothing', () async {
      await expectLater(
        manager.updateTaskIcon('nonexistent', Icons.star),
        completes,
      );
      expect(manager.taskTypeColors.containsKey('nonexistent'), isFalse);
    });

    // taskTypeColors should expose all defaults as a complete map
    test('taskTypeColors includes all 7 default types', () async {
      final colors = manager.taskTypeColors;
      expect(colors.keys, containsAll([
        'medication', 'appointment', 'exercise',
        'general', 'lab', 'pharmacy', 'imported',
      ]));
      expect(colors.length, equals(7));
    });

    // Verify the default icon/color values for each built-in task type
    test('default task types have correct icons', () async {
      expect(manager.getIcon('medication'), Icons.medication);
      expect(manager.getIcon('appointment'), Icons.event);
      expect(manager.getIcon('exercise'), Icons.fitness_center);
      expect(manager.getIcon('general'), Icons.task);
      expect(manager.getIcon('lab'), Icons.science);
      expect(manager.getIcon('pharmacy'), Icons.local_pharmacy);
      expect(manager.getIcon('imported'), Icons.file_upload);
    });

    test('default task types have correct colors', () async {
      expect(manager.getColor('medication').toARGB32(), Colors.red.toARGB32());
      expect(manager.getColor('appointment').toARGB32(), Colors.blue.toARGB32());
      expect(manager.getColor('exercise').toARGB32(), Colors.green.toARGB32());
      expect(manager.getColor('general').toARGB32(), Colors.deepOrange.toARGB32());
      expect(manager.getColor('lab').toARGB32(), Colors.pink.toARGB32());
      expect(manager.getColor('pharmacy').toARGB32(), Colors.teal.toARGB32());
      expect(manager.getColor('imported').toARGB32(), Colors.purple.toARGB32());
    });

    // loadFromPrefs with corrupted JSON should silently fall back to defaults
    test('_loadFromPrefs with invalid JSON falls back to defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('task_type_settings', 'not-valid-json{{}}');

      final manager2 = TaskTypeManager();
      await Future.delayed(const Duration(milliseconds: 10));

      // Defaults should be restored after a parse error
      expect(manager2.taskTypeColors.containsKey('medication'), isTrue);
      expect(manager2.taskTypeColors.length, equals(7));
    });

    // notifyListeners should be called so that ChangeNotifier listeners fire
    test('addTaskType notifies listeners', () async {
      int callCount = 0;
      manager.addListener(() => callCount++);

      await manager.addTaskType('diet', Colors.orange);

      expect(callCount, greaterThan(0));
    });

    test('removeTaskType notifies listeners', () async {
      await manager.addTaskType('temp', Colors.grey);
      int callCount = 0;
      manager.addListener(() => callCount++);

      await manager.removeTaskType('temp');

      expect(callCount, greaterThan(0));
    });

    test('resetDefaults notifies listeners', () async {
      int callCount = 0;
      manager.addListener(() => callCount++);

      await manager.resetDefaults();

      expect(callCount, greaterThan(0));
    });

    // removeTaskType on a key that doesn't exist should be a silent no-op
    test('removeTaskType on non-existent key is a no-op', () async {
      final countBefore = manager.taskTypeColors.length;
      await manager.removeTaskType('does_not_exist');
      expect(manager.taskTypeColors.length, equals(countBefore));
    });

    // getSortedTypes returns an alphabetically ordered list
    test('getSortedTypes returns alphabetically ordered keys', () async {
      final sorted = manager.getSortedTypes();
      final copy = List<String>.from(sorted)..sort();
      expect(sorted, orderedEquals(copy));
    });
  });
}

// R01: schema v1 (T22 §5.2) and its committed snapshot.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/db/app_database.dart';

import '../../helpers/app_harness.dart';

Future<Map<String, (String, bool, bool)>> _columns(
  AppDatabase db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {
    for (final r in rows)
      r.read<String>('name'): (
        r.read<String>('type'),
        r.read<int>('notnull') == 0,
        r.read<int>('pk') > 0,
      ),
  };
}

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  test('R01 trips columns, types, nullability, primary key', () async {
    expect(db.schemaVersion, 1);
    // (type, nullable, primary key)
    expect(await _columns(db, 'trips'), {
      'id': ('TEXT', false, true),
      'destination_name': ('TEXT', false, false),
      'destination_detail': ('TEXT', true, false),
      'destination_kind': ('TEXT', false, false),
      'dest_lat': ('REAL', false, false),
      'dest_lng': ('REAL', false, false),
      'dest_source': ('TEXT', false, false),
      'mode': ('TEXT', false, false),
      'distance_threshold_m': ('INTEGER', true, false),
      'time_threshold_min': ('INTEGER', true, false),
      'pre_alert_enabled': ('INTEGER', false, false),
      'vehicle_hint': ('TEXT', false, false),
      'simulated': ('INTEGER', false, false),
      'started_at': ('INTEGER', false, false),
      'ended_at': ('INTEGER', true, false),
      'result': ('TEXT', true, false),
      'end_reason': ('TEXT', true, false),
      'alarm_at': ('INTEGER', true, false),
      'alarm_reason': ('TEXT', true, false),
      'dismissed_at': ('INTEGER', true, false),
      'snooze_count': ('INTEGER', false, false),
      'travelled_m': ('INTEGER', true, false),
      'vehicle_guess': ('TEXT', true, false),
    });
  });

  test('R01 saved_places columns', () async {
    expect(await _columns(db, 'saved_places'), {
      'slot': ('TEXT', false, true),
      'name': ('TEXT', false, false),
      'detail': ('TEXT', true, false),
      'kind': ('TEXT', false, false),
      'lat': ('REAL', false, false),
      'lng': ('REAL', false, false),
      'updated_at': ('INTEGER', false, false),
    });
  });

  test('R01 index on trips.started_at', () async {
    final indexes = await db.customSelect('PRAGMA index_list(trips)').get();
    expect(
      indexes.map((r) => r.read<String>('name')),
      contains('trips_started_at'),
    );
    final info = await db
        .customSelect('PRAGMA index_info(trips_started_at)')
        .get();
    expect(info.map((r) => r.read<String>('name')), ['started_at']);
  });

  test('R01 drift_schema_v1.json is committed with both tables', () {
    final file = File('drift_schemas/app/drift_schema_v1.json');
    expect(file.existsSync(), isTrue);
    final text = file.readAsStringSync();
    final json = jsonDecode(text) as Map<String, dynamic>;
    expect(json, isNotEmpty);
    expect(text, contains('"trips"'));
    expect(text, contains('"saved_places"'));
    expect(text, contains('"simulated"'));
    expect(text, contains('"result"'));
    // Only one schema version so far.
    expect(
      Directory('drift_schemas/app')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('drift_schema_v')),
      ['drift_schema_v1.json'],
    );
  });
}

// Tester additions for T14.1 (beyond D01/D08/D09): wire layout of the new
// messages, the InterruptionFilterMsg index on all three generated files,
// engineParamsJson length semantics (UTF-16, like the native V11), every
// deviceStatus() value through CoreBridge, and privacy of the new names in the
// generated code.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

import 'bridge_samples.dart';

const _prefix = 'dev.flutter.pigeon.napstop';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Object? _roundTrip(Object? value) {
  const codec = TripHostApi.pigeonChannelCodec;
  return codec.decodeMessage(codec.encodeMessage(value));
}

String _generated(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InterruptionFilterMsg', () {
    const order = ['unknown', 'all', 'priority', 'alarms', 'none'];

    test('Dart: wire value is the index, not INTERRUPTION_FILTER_*', () {
      expect(InterruptionFilterMsg.values.map((v) => v.name), order);
      // Platform NONE = 3 / ALARMS = 4; on the wire it is the other way.
      expect(InterruptionFilterMsg.none.index, 4);
      expect(InterruptionFilterMsg.alarms.index, 3);
    });

    test('Kotlin and Swift generated enums use the same values', () {
      final kotlin =
          RegExp(r'enum class InterruptionFilterMsg\(val raw: Int\) \{([^;]*);')
              .firstMatch(
                _generated(
                  'android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt',
                ),
              );
      expect(kotlin, isNotNull);
      expect(
        RegExp(r'(\w+)\((\d+)\)')
            .allMatches(kotlin![1]!)
            .map((m) => '${m[1]!.toLowerCase()}=${m[2]}')
            .toList(),
        [for (var i = 0; i < order.length; i++) '${order[i]}=$i'],
      );

      final swift = RegExp(
        r'enum InterruptionFilterMsg: Int, CaseIterable \{([^}]*)\}',
      ).firstMatch(_generated('ios/Runner/Bridge/CoreApi.g.swift'));
      expect(swift, isNotNull);
      expect(
        RegExp(r'case (\w+) = (\d+)')
            .allMatches(swift![1]!)
            .map((m) => '${m[1]}=${m[2]}')
            .toList(),
        [for (var i = 0; i < order.length; i++) '${order[i]}=$i'],
      );
    });

    test('every value survives the codec inside DeviceStatusMsg', () {
      for (final filter in InterruptionFilterMsg.values) {
        final msg = DeviceStatusMsg(interruptionFilter: filter);
        final back = _roundTrip(msg)! as DeviceStatusMsg;
        expect(back.interruptionFilter, filter);
        expect(back, msg);
      }
    });
  });

  group('DeviceStatusMsg wire layout', () {
    test('six fields in spec order, filter required', () {
      final full = DeviceStatusMsg(
        batteryPct: 15,
        charging: true,
        alarmVolumePct: 86,
        alarmMuted: false,
        interruptionFilter: InterruptionFilterMsg.priority,
        priorityAllowsAlarms: false,
      );
      expect(full.encode(), [
        15,
        true,
        86,
        false,
        InterruptionFilterMsg.priority,
        false,
      ]);
      final empty = DeviceStatusMsg(
        interruptionFilter: InterruptionFilterMsg.unknown,
      );
      expect(empty.encode(), [
        null,
        null,
        null,
        null,
        InterruptionFilterMsg.unknown,
        null,
      ]);
    });

    test('Kotlin and Swift read the fields in the same order', () {
      const fields = [
        'batteryPct',
        'charging',
        'alarmVolumePct',
        'alarmMuted',
        'interruptionFilter',
        'priorityAllowsAlarms',
      ];
      for (final path in [
        'android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt',
        'ios/Runner/Bridge/CoreApi.g.swift',
      ]) {
        final code = _generated(path);
        final start = code.indexOf(RegExp('(class|struct) DeviceStatusMsg'));
        expect(start, greaterThan(0), reason: path);
        final body = code.substring(start, code.indexOf('toList', start));
        for (var i = 0; i < fields.length; i++) {
          // Kotlin: `val batteryPct = pigeonVar_list[0] as Long?`
          // Swift: `let batteryPct: Int64? = nilOrValue(pigeonVar_list[0])`
          expect(
            body,
            contains(RegExp('\\b${fields[i]}\\b[^\\n]*pigeonVar_list\\[$i\\]')),
            reason: '${fields[i]} in $path',
          );
        }
      }
    });

    test('extreme values survive the codec', () {
      for (final msg in [
        DeviceStatusMsg(
          batteryPct: 0,
          charging: false,
          alarmVolumePct: 0,
          alarmMuted: true,
          interruptionFilter: InterruptionFilterMsg.none,
        ),
        DeviceStatusMsg(
          batteryPct: 100,
          charging: true,
          alarmVolumePct: 100,
          alarmMuted: false,
          interruptionFilter: InterruptionFilterMsg.priority,
          priorityAllowsAlarms: true,
        ),
      ]) {
        expect(_roundTrip(msg), msg);
      }
    });
  });

  group('engineParamsJson length', () {
    test('V11 counts UTF-16 code units, like Dart String.length', () {
      // 8 192 emoji: 8 192 code points, 16 384 code units, 32 768 UTF-8 bytes.
      final emoji = '\u{1F634}' * 8192;
      expect(emoji.length, 16384);
      expect(emoji.runes.length, 8192);
      final back = _roundTrip(sampleConfig()..engineParamsJson = emoji)!;
      expect((back as TripConfigMsg).engineParamsJson, emoji);
      expect(back.engineParamsJson!.length, 16384);
    });

    test('characters a snapshot or log could mangle are kept', () {
      for (final json in [
        '{"k": "a=b:c #d !e \\\\f"}\n',
        '\r\n\t\u0000\u000c',
        String.fromCharCodes(const [0xa0, 0x2028, 0x2029, 0xfeff]),
        'ặ ẫ ở ữ đ Ư',
        ' ',
      ]) {
        final back =
            _roundTrip(sampleConfig()..engineParamsJson = json)!
                as TripConfigMsg;
        expect(back.engineParamsJson, json);
      }
    });

    test('T14 callers that never set it send null as the 9th field', () {
      final wire = sampleConfig(nulls: true).encode() as List<Object?>;
      expect(wire, hasLength(9));
      expect(wire[8], isNull);
    });
  });

  group('CoreBridge.deviceStatus', () {
    tearDown(
      () => _messenger.setMockMessageHandler(
        '$_prefix.PermissionHostApi.deviceStatus',
        null,
      ),
    );

    test('every filter and nullability reaches the caller unchanged', () async {
      final bridge = CoreBridge();
      for (final filter in InterruptionFilterMsg.values) {
        for (final status in [
          DeviceStatusMsg(interruptionFilter: filter),
          DeviceStatusMsg(
            batteryPct: 15,
            charging: false,
            alarmVolumePct: 0,
            alarmMuted: true,
            interruptionFilter: filter,
            priorityAllowsAlarms: filter == InterruptionFilterMsg.priority
                ? false
                : null,
          ),
        ]) {
          _messenger.setMockDecodedMessageHandler<Object?>(
            const BasicMessageChannel<Object?>(
              '$_prefix.PermissionHostApi.deviceStatus',
              TripHostApi.pigeonChannelCodec,
            ),
            (_) async => [status],
          );
          expect(await bridge.deviceStatus(), status);
        }
      }
    });

    test('a null reply is a BridgeException, not a crash', () async {
      _messenger.setMockDecodedMessageHandler<Object?>(
        const BasicMessageChannel<Object?>(
          '$_prefix.PermissionHostApi.deviceStatus',
          TripHostApi.pigeonChannelCodec,
        ),
        (_) async => [null],
      );
      await expectLater(
        CoreBridge().deviceStatus(),
        throwsA(isA<BridgeException>()),
      );
    });
  });

  group('D09 privacy of the T14.1 names in the generated code', () {
    const newNames = [
      'engineParamsJson',
      'batteryPct',
      'charging',
      'alarmVolumePct',
      'alarmMuted',
      'interruptionFilter',
      'priorityAllowsAlarms',
      'DeviceStatusMsg',
      'InterruptionFilterMsg',
      'deviceStatus',
    ];

    for (final path in [
      'pigeons/core_api.dart',
      'lib/core/bridge/core_api.g.dart',
      'android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt',
      'ios/Runner/Bridge/CoreApi.g.swift',
    ]) {
      test('$path declares every new name', () {
        final code = _generated(path);
        for (final name in newNames) {
          expect(code, contains(name), reason: '$name in $path');
        }
      });
    }

    test('DeviceStatusMsg has no coordinate-like field in any file', () {
      const coordinateWords = {
        'lat',
        'lng',
        'lon',
        'latitude',
        'longitude',
        'coord',
        'coords',
        'coordinate',
        'coordinates',
        'geo',
        'position',
        'e7',
      };
      for (final path in [
        'pigeons/core_api.dart',
        'lib/core/bridge/core_api.g.dart',
        'android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt',
        'ios/Runner/Bridge/CoreApi.g.swift',
      ]) {
        final code = _generated(path);
        final start = code.indexOf(RegExp('(class|struct) DeviceStatusMsg'));
        expect(start, greaterThan(0), reason: path);
        // Top-level declaration: it ends at the first `}` in column 0.
        final end = code.indexOf('\n}', start);
        expect(end, greaterThan(start), reason: path);
        final body = code
            .substring(start, end)
            .split('\n')
            .map((l) => l.replaceFirst(RegExp('//.*'), ''))
            .join('\n');
        final identifiers = RegExp(r'[A-Za-z_]\w*')
            .allMatches(body)
            .map((m) => m[0]!)
            .toSet();
        // "along"/"Long"/"toLong" would match "lon": compare whole words of
        // each identifier, as bridge_generated_scan_test does.
        final hits = identifiers.where((id) {
          final words = id
              .replaceAllMapped(
                RegExp('([a-z0-9])([A-Z])'),
                (m) => '${m[1]}_${m[2]}',
              )
              .toLowerCase()
              .split('_');
          return words.any(coordinateWords.contains);
        }).toList();
        expect(hits, isEmpty, reason: path);
      }
    });

    test('engineParamsJson and deviceStatus never reach a log call', () {
      // Hand-written bridge code, all platforms (spec: "Không log").
      final files = [
        ...Directory('lib/core/bridge').listSync(recursive: true),
        ...Directory('android/app/src/main/kotlin/app/napstop/core/bridge')
            .listSync(recursive: true),
        ...Directory('ios/Runner/Bridge').listSync(recursive: true),
      ].whereType<File>().where((f) => !f.path.contains('.g.')).toList();
      expect(files.length, greaterThanOrEqualTo(8));
      final logCall = RegExp(
        r'(Log\.[vdiwe]|print\(|debugPrint\(|NSLog\(|os_log\(|Logger\(|logger\.)[^\n]*',
      );
      for (final f in files) {
        for (final m in logCall.allMatches(f.readAsStringSync())) {
          final line = m[0]!;
          for (final banned in [
            'engineParamsJson',
            'config',
            'batteryPct',
            'level',
          ]) {
            expect(
              line.contains(banned),
              isFalse,
              reason: '$banned logged in ${f.path}: $line',
            );
          }
        }
      }
    });
  });
}

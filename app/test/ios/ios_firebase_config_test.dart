// T29.2 FU03–FU06: static checks of the iOS Firebase configuration (repo
// files only, no macOS needed).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Minimal XML plist reader: dict, array, key, string, true/false, integer,
/// real. Enough for Info.plist and PrivacyInfo.xcprivacy.
Object? parsePlist(String xml) {
  final tokens = RegExp(r'<(/?)(\w+)(/?)>([^<]*)').allMatches(xml).toList();
  var i = 0;
  Object? value() {
    while (i < tokens.length) {
      final t = tokens[i++];
      final closing = t.group(1)!.isNotEmpty;
      final tag = t.group(2)!;
      final empty = t.group(3)!.isNotEmpty;
      final text = t.group(4)!;
      if (closing || tag == 'plist') {
        if (closing && (tag == 'dict' || tag == 'array')) {
          return _End.instance;
        }
        continue;
      }
      switch (tag) {
        case 'dict':
          final map = <String, Object?>{};
          if (empty) {
            return map;
          }
          while (true) {
            final k = value();
            if (k is _End) {
              return map;
            }
            map[k! as String] = value();
          }
        case 'array':
          final list = <Object?>[];
          if (empty) {
            return list;
          }
          while (true) {
            final v = value();
            if (v is _End) {
              return list;
            }
            list.add(v);
          }
        case 'key' || 'string':
          return empty ? '' : _unescape(text);
        case 'true':
          return true;
        case 'false':
          return false;
        case 'integer':
          return int.parse(text.trim());
        case 'real':
          return double.parse(text.trim());
      }
    }
    return _End.instance;
  }

  return value();
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

final class _End {
  const new _();
  static const _End instance = _End._();
}

Map<String, Object?> _plist(String path) =>
    parsePlist(File(path).readAsStringSync())! as Map<String, Object?>;

/// Swift source without `//` line comments.
String _swiftCode(File f) => f
    .readAsStringSync()
    .split('\n')
    .map((l) => l.replaceFirst(RegExp('//.*'), ''))
    .join('\n');

final RegExp _crashCall = RegExp(
  r'\b(fatalError|preconditionFailure|precondition|assertionFailure|assert)\(',
);

/// Crash calls whose message is not a plain literal (interpolation or a
/// non-literal message). One entry per offending call: `name: rest`.
List<String> nonLiteralCrashMessages(String code) {
  final bad = <String>[];
  for (final m in _crashCall.allMatches(code)) {
    final name = m.group(1)!;
    final rest = code.substring(m.end).split('\n').first;
    if (rest.contains(r'\(')) {
      bad.add('$name: $rest');
      continue;
    }
    // Message-only calls: nothing, or a string literal.
    if (name == 'fatalError' ||
        name == 'preconditionFailure' ||
        name == 'assertionFailure') {
      final arg = rest.trimLeft();
      if (!arg.startsWith(')') && !arg.startsWith('"')) {
        bad.add('$name: $rest');
      }
    }
  }
  return bad;
}

const _collectionKeys = [
  'FirebaseCrashlyticsCollectionEnabled',
  'FIREBASE_ANALYTICS_COLLECTION_ENABLED',
  'GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED',
  'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS',
  'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE',
  'GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA',
  'FirebaseAutomaticScreenReportingEnabled',
];

void main() {
  test('plist reader', () {
    final p = parsePlist(
      '<plist><dict><key>a</key><array><string>x &amp; y</string><true/> '
      '</array><key>b</key><dict/><key>c</key><false></false>'
      '<key>d</key><integer> 3 </integer></dict></plist>',
    );
    expect(p, {
      'a': ['x & y', true],
      'b': <String, Object?>{},
      'c': false,
      'd': 3,
    });
  });

  test('FU03 Info.plist: collection off before Dart runs', () {
    final info = _plist('ios/Runner/Info.plist');
    for (final k in _collectionKeys) {
      expect(info.containsKey(k), isTrue, reason: k);
      expect(info[k], isFalse, reason: k);
    }
    for (final k in const [
      'FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED',
      'FirebaseDataCollectionDefaultEnabled',
      'NSUserTrackingUsageDescription',
      'NSLocationAlwaysAndWhenInUseUsageDescription',
    ]) {
      expect(info.containsKey(k), isFalse, reason: k);
    }
    // Raw text too: each key is followed by <false/>.
    final raw = File('ios/Runner/Info.plist').readAsStringSync();
    for (final k in _collectionKeys) {
      expect(
        RegExp('<key>$k</key>\\s*<false/>').hasMatch(raw),
        isTrue,
        reason: k,
      );
    }
  });

  test('FU04 PrivacyInfo.xcprivacy: the four Firebase data types', () {
    final p = _plist('ios/Runner/PrivacyInfo.xcprivacy');
    expect(p['NSPrivacyTracking'], isFalse);
    expect(p['NSPrivacyTrackingDomains'], isEmpty);
    const analytics = 'NSPrivacyCollectedDataTypePurposeAnalytics';
    const function = 'NSPrivacyCollectedDataTypePurposeAppFunctionality';
    final want = <String, Set<String>>{
      'NSPrivacyCollectedDataTypeProductInteraction': {analytics},
      'NSPrivacyCollectedDataTypeCrashData': {function},
      'NSPrivacyCollectedDataTypeOtherDiagnosticData': {function},
      'NSPrivacyCollectedDataTypeDeviceID': {analytics, function},
    };
    final types = (p['NSPrivacyCollectedDataTypes']! as List)
        .cast<Map<String, Object?>>();
    final got = <String, Set<String>>{};
    for (final t in types) {
      final name = t['NSPrivacyCollectedDataType']! as String;
      expect(t['NSPrivacyCollectedDataTypeLinked'], isFalse, reason: name);
      expect(t['NSPrivacyCollectedDataTypeTracking'], isFalse, reason: name);
      got[name] = {
        ...(t['NSPrivacyCollectedDataTypePurposes']! as List).cast<String>(),
      };
    }
    expect(types, hasLength(want.length), reason: 'no duplicate entry');
    expect(got, want);
    expect(got.keys.where((k) => k.contains('Location')), isEmpty);
    final apis = <String, List<Object?>>{
      for (final a
          in (p['NSPrivacyAccessedAPITypes']! as List)
              .cast<Map<String, Object?>>())
        a['NSPrivacyAccessedAPIType']! as String:
            a['NSPrivacyAccessedAPITypeReasons']! as List<Object?>,
    };
    expect(apis, {
      'NSPrivacyAccessedAPICategoryUserDefaults': ['CA92.1'],
      'NSPrivacyAccessedAPICategorySystemBootTime': ['35F9.1'],
      'NSPrivacyAccessedAPICategoryFileTimestamp': ['C617.1'],
    });
  });

  group('FU05 Swift never calls Firebase; crash messages are literals', () {
    final files = [
      ...Directory('ios/Runner').listSync(recursive: true),
      ...Directory('ios/Core/Sources').listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.swift')).toList();

    test('scanned files', () {
      expect(files.length, greaterThan(20));
    });

    test('no Firebase API in Swift', () {
      final forbidden = RegExp(
        r'import\s+Firebase|\bFirebaseCrashlytics\b|\bFirebaseAnalytics\b|'
        r'Crashlytics\.crashlytics\(|Analytics\.logEvent\(',
      );
      for (final f in files) {
        expect(forbidden.hasMatch(_swiftCode(f)), isFalse, reason: f.path);
      }
    });

    test('fatalError / precondition / assert messages are literals', () {
      var calls = 0;
      for (final f in files) {
        final code = _swiftCode(f);
        calls += _crashCall.allMatches(code).length;
        expect(nonLiteralCrashMessages(code), isEmpty, reason: f.path);
      }
      expect(calls, greaterThanOrEqualTo(4), reason: 'the scan sees them');
    });

    test('negative control', () {
      expect(nonLiteralCrashMessages(r'fatalError("x \(lat)")'), hasLength(1));
      expect(nonLiteralCrashMessages('fatalError(message)'), hasLength(1));
      expect(
        nonLiteralCrashMessages(r'precondition(ok, "v \(v)")'),
        hasLength(1),
      );
      expect(
        nonLiteralCrashMessages('fatalError("T29.2 native probe")'),
        isEmpty,
      );
      expect(nonLiteralCrashMessages('precondition(a, "samples")'), isEmpty);
      expect(nonLiteralCrashMessages('fatalError()'), isEmpty);
    });
  });

  test('FU06 ios-compile.yml: no IDFA build env, Firebase CI checks', () {
    final yml = File('../.github/workflows/ios-compile.yml')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final env = RegExp(
      r'^env:\n((?:  .*\n)+)',
      multiLine: true,
    ).firstMatch(yml);
    expect(env, isNotNull, reason: 'workflow-level env');
    expect(
      env!.group(1),
      contains("  FIREBASE_ANALYTICS_WITHOUT_ADID: 'true'"),
    );
    final start = yml.indexOf('\n  ios-device:\n');
    expect(start, greaterThan(0));
    final next = RegExp(r'\n  [a-z][\w-]*:\n')
        .firstMatch(yml.substring(start + 1));
    final job = next == null
        ? yml.substring(start)
        : yml.substring(start, start + 1 + next.start);
    for (final call in const [
      'firebase-ci-check.sh --self-test',
      'firebase-ci-check.sh check ',
      'firebase-ci-check.sh upload-dsyms ',
    ]) {
      expect(job, contains(call));
    }
    expect(job, contains('napstop-ios-dsyms'));
  });
}

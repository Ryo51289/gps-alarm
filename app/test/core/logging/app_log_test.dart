// T29 TC21: AppLog levels and redaction, release vs debug.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/telemetry/crash/safe_diagnostic.dart';

/// Shaped like sqlite3's SqliteException: quotes the bound parameters.
final class _FakeSqliteException implements Exception {
  const new();

  @override
  String toString() =>
      'SqliteException(19): UNIQUE constraint failed, '
      'Causing statement: INSERT INTO trips VALUES (?, ?), '
      "parameters: ['Ga Đồng Hới', 17.4783]";
}

final class _Safe implements SafeDiagnostic {
  const new();

  @override
  String toString() => '_Safe(16.4637211)';
}

void main() {
  final log = AppLog.named('test');

  test('names are prefixed', () {
    expect(log.fullName, 'napstop.test');
  });

  test('TC21 release: INFO and above become redacted breadcrumbs', () async {
    final crumbs = <String>[];
    final console = <String>[];
    AppLog.configure(
      isRelease: true,
      breadcrumb: crumbs.add,
      console: (m, {required name, required level}) => console.add(m),
    );
    log
      ..fine('fine 1')
      ..info('fix 21.0285123')
      ..severe('failed', StateError('at 105.8542123'), StackTrace.current);
    await pumpEventQueue();
    expect(crumbs, [
      '[INFO] napstop.test: fix <num>',
      '[SEVERE] napstop.test: failed | StateError',
    ]);
    expect(console, isEmpty);
  });

  test(
    'TC21 debug: everything to the console, redacted; no breadcrumb',
    () async {
      final crumbs = <String>[];
      final console = <(String, String, int)>[];
      AppLog.configure(
        isRelease: false,
        breadcrumb: crumbs.add,
        console: (m, {required name, required level}) =>
            console.add((m, name, level)),
      );
      log
        ..fine('fine lat=21.02')
        ..warning('w', StateError('16.4637211'));
      await pumpEventQueue();
      expect(crumbs, isEmpty);
      expect(console, [
        ('fine lat=<redacted>', 'napstop.test', 500),
        ('w | Bad state: <num>', 'napstop.test', 900),
      ]);
    },
  );

  test('round 2: release keeps only the error type (SQL parameters)', () async {
    final crumbs = <String>[];
    AppLog.configure(isRelease: true, breadcrumb: crumbs.add);
    log
      ..warning('history write failed', const _FakeSqliteException())
      ..warning('rule', const _Safe());
    await pumpEventQueue();
    expect(crumbs, [
      '[WARNING] napstop.test: history write failed | _FakeSqliteException',
      '[WARNING] napstop.test: rule | _Safe(<num>)',
    ]);
    for (final c in crumbs) {
      expect(c, isNot(contains('Đồng Hới')));
    }
  });

  test('configure again replaces the listener', () async {
    final a = <String>[];
    final b = <String>[];
    AppLog.configure(isRelease: true, breadcrumb: a.add);
    AppLog.configure(isRelease: true, breadcrumb: b.add);
    log.info('x');
    await pumpEventQueue();
    expect(a, isEmpty);
    expect(b, ['[INFO] napstop.test: x']);
  });
}

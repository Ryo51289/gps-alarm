// T29 TC08: redact.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/redaction/redactor.dart';

void main() {
  test('TC08 coordinates and key/value pairs are masked', () {
    final a = redact('Fix 21.0285123, 105.8542123 rejected');
    expect(a, 'Fix <num>, <num> rejected');
    expect(redact('destLat=95'), 'destLat=<redacted>');
    expect(redact('geo:16.4637,107.59'), isNot(contains('16.4637')));
    expect(redact('lat: 21'), 'lat=<redacted>');
    expect(redact('LONGITUDE = -105.85 ok'), 'LONGITUDE=<redacted> ok');
    expect(redact('lng=-6,2'), 'lng=<redacted>');
    expect(redact('Took 1.5 s'), 'Took 1.5 s');
    expect(redact('-6.20000'), '<num>');
  });

  test('TC08 long input is cut to 1024 + ellipsis', () {
    final long = redact('x' * 5000);
    expect(long.length, 1025);
    expect(long.endsWith('…'), isTrue);
    // Never inside a surrogate pair.
    final emoji = redact('${'x' * 1023}😀tail');
    expect(emoji.length, 1024);
    expect(emoji, '${'x' * 1023}…');
  });

  test('TC08 idempotent', () {
    for (final s in [
      'Fix 21.0285123, 105.8542123 rejected',
      'destLat=95 destLng: 105.1',
      'lat: 21',
      'x' * 5000,
      '${'x' * 1023}😀tail',
      'Took 1.5 s',
      '',
    ]) {
      expect(redact(redact(s)), redact(s), reason: s);
    }
  });
}

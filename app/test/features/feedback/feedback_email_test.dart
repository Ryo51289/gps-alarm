// T28.4 U01-U13: pure builders of the feedback email.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';

import '../../helpers/fake_core_bridge.dart';

const FeedbackCopy _vi = FeedbackCopy(
  subjectWord: 'Góp ý',
  prompt: 'Viết góp ý của bạn ở đây:',
  diagHeader:
      'Thông tin máy để tìm lỗi. Không có vị trí của bạn. '
      'Bạn có thể xoá phần này.',
);

const FeedbackCopy _en = FeedbackCopy(
  subjectWord: 'Feedback',
  prompt: 'Write your feedback here:',
  diagHeader:
      'Device info for troubleshooting. It has no location. '
      'You may delete it.',
);

DeviceInfoMsg _android({
  String manufacturer = 'Xiaomi',
  String model = '23078PND5G',
  String osVersion = '15',
  int? sdk = 35,
}) => DeviceInfoMsg(
  platform: PlatformMsg.android,
  manufacturer: manufacturer,
  brand: manufacturer.toLowerCase(),
  model: model,
  osVersion: osVersion,
  androidSdkInt: sdk,
);

DeviceInfoMsg _ios({String osVersion = '26.1', String model = 'iPhone'}) =>
    DeviceInfoMsg(
      platform: PlatformMsg.ios,
      manufacturer: 'Apple',
      brand: 'Apple',
      model: model,
      osVersion: osVersion,
      iosMajor: 26,
    );

FeedbackDiagnostics _diag({
  String? version = '0.1.0',
  String? build = '1',
  AppFlavor flavor = AppFlavor.prod,
  DeviceInfoMsg? device,
  PermissionStatusMsg? permissions,
  bool noDevice = false,
  bool noPermissions = false,
  AppLanguage language = AppLanguage.system,
  String locale = 'vi-VN',
  String? paramsId = 'default',
}) => FeedbackDiagnostics(
  appVersion: version,
  appBuild: build,
  flavor: flavor,
  device: noDevice ? null : device ?? _android(),
  permissions: noPermissions
      ? null
      : permissions ??
            androidPermissions(
              location: LocationAccessMsg.always,
              batteryOptimizationIgnored: PermissionStateMsg.denied,
            ),
  appLanguage: language,
  deviceLocale: locale,
  paramsId: paramsId,
);

void main() {
  test('U01 address and app name', () {
    expect(kFeedbackEmail, 'giftff02@gmail.com');
    final app = diagnosticsLines(_diag()).first;
    expect(app, 'App: $kAppName 0.1.0 (1), prod');
  });

  test('U02 subject with version', () {
    expect(feedbackSubject(_vi, _diag()), '[NapStop] Góp ý — 0.1.0 (1)');
    expect(feedbackSubject(_en, _diag()), '[NapStop] Feedback — 0.1.0 (1)');
  });

  test('U03 subject without version / build', () {
    expect(feedbackSubject(_vi, _diag(version: null)), '[NapStop] Góp ý');
    expect(feedbackSubject(_vi, _diag(build: '')), '[NapStop] Góp ý — 0.1.0');
    expect(feedbackSubject(_vi, _diag(build: null)), '[NapStop] Góp ý — 0.1.0');
  });

  test('U04 deviceLabel does not repeat the maker', () {
    expect(deviceLabel(_android()), 'Xiaomi 23078PND5G');
    expect(
      deviceLabel(_android(manufacturer: 'Google', model: 'Pixel 8')),
      'Google Pixel 8',
    );
    expect(
      deviceLabel(_android(manufacturer: 'samsung', model: 'samsung SM-S918B')),
      'samsung SM-S918B',
    );
    expect(
      deviceLabel(_android(manufacturer: 'Samsung', model: 'SAMSUNG X')),
      'SAMSUNG X',
    );
    expect(deviceLabel(_ios()), 'iPhone');
  });

  test('U05 deviceLabel strips control chars, cuts, unknown', () {
    final long = 'A\nB\rC\tD${'x' * 80}';
    final label = deviceLabel(_android(manufacturer: 'Maker\t', model: long));
    expect(label, isNot(contains(RegExp(r'[\x00-\x1F\x7F]'))));
    expect(label.startsWith('Maker A B C D'), isTrue);
    // Each part ≤ 40 characters: "Maker" + " " + 40.
    expect(label.length, lessThanOrEqualTo(5 + 1 + kFeedbackFieldMaxChars));
    final modelOnly = deviceLabel(_android(manufacturer: '', model: long));
    expect(modelOnly.length, lessThanOrEqualTo(kFeedbackFieldMaxChars));
    expect(deviceLabel(_android(manufacturer: '', model: '')), 'unknown');
    expect(deviceLabel(_android(manufacturer: ' ', model: '\n')), 'unknown');
    expect(deviceLabel(_ios(model: '')), 'unknown');
  });

  test('U06 osLabel', () {
    expect(osLabel(_android()), 'Android 15 (API 35)');
    expect(osLabel(_ios()), 'iOS 26.1');
    expect(osLabel(_android(osVersion: '', sdk: 34)), 'Android (API 34)');
    expect(osLabel(_android(sdk: null)), 'Android 15');
    expect(osLabel(_ios(osVersion: '')), 'iOS');
  });

  test('U07 permissionsLabel on Android leaves alarmkit out', () {
    final s = permissionsLabel(
      androidPermissions(
        location: LocationAccessMsg.always,
        batteryOptimizationIgnored: PermissionStateMsg.denied,
      ),
    );
    expect(
      s,
      'location=always, precise=granted, location_services=on, '
      'notifications=granted, full_screen=granted, exact_alarm=granted, '
      'battery_unrestricted=denied',
    );
    expect(s, isNot(contains('alarmkit')));
    expect(
      permissionsLabel(
        androidPermissions(
          location: LocationAccessMsg.notDetermined,
          locationServicesEnabled: false,
        ),
      ),
      startsWith(
        'location=notDetermined, precise=granted, '
        'location_services=off',
      ),
    );
  });

  test('U08 permissionsLabel on iOS leaves the Android entries out', () {
    final s = permissionsLabel(
      iosPermissions(location: LocationAccessMsg.always),
    );
    expect(
      s,
      'location=always, precise=granted, location_services=on, '
      'notifications=granted, alarmkit=granted',
    );
    expect(s, isNot(contains('full_screen')));
    expect(s, isNot(contains('exact_alarm')));
    expect(s, isNot(contains('battery_unrestricted')));
  });

  test('U09 mailto encoding (RFC 6068)', () {
    const subject = '[NapStop] Góp ý — a&b+c?d=e#f%g';
    const body = 'Dòng 1 có dấu\r\nline 2 & + ? = # %';
    final s = feedbackMailtoUri(
      to: kFeedbackEmail,
      subject: subject,
      body: body,
    ).toString();
    expect(s, startsWith('mailto:giftff02@gmail.com?subject='));
    expect(s, isNot(contains('+')));
    expect(s, isNot(contains(' ')));
    expect(s, contains('%20'));
    expect(s, contains('%2B'));
    expect(s, contains('%26'));
    expect(s, contains('%0D%0A'));
    expect(s, contains('%C3%B3'));
    final query = s.substring(s.indexOf('?') + 1);
    final parts = query.split('&');
    expect(parts, hasLength(2));
    expect(parts[0], startsWith('subject='));
    expect(parts[1], startsWith('body='));
    expect(Uri.decodeComponent(parts[0].substring(8)), subject);
    expect(Uri.decodeComponent(parts[1].substring(5)), body);
    final uri = Uri.parse(s);
    expect(uri.scheme, 'mailto');
    expect(uri.path, kFeedbackEmail);
  });

  test('U10 encoded URI stays short', () {
    for (final copy in [_vi, _en]) {
      for (final device in [
        _android(manufacturer: 'M' * 40, model: 'x' * 40),
        _ios(model: 'y' * 40),
      ]) {
        final d = _diag(
          device: device,
          paramsId: 'a1b2c3d4',
          permissions: device.platform == PlatformMsg.ios
              ? iosPermissions()
              : null,
        );
        final body = feedbackBody(copy, d);
        expect(body.length, lessThan(700));
        final uri = feedbackMailtoUri(
          to: kFeedbackEmail,
          subject: feedbackSubject(copy, d),
          body: body,
        );
        expect(uri.toString().length, lessThan(2000));
      }
    }
  });

  test('U11 body layout', () {
    const permissions =
        'Permissions: location=always, precise=granted, location_services=on, '
        'notifications=granted, full_screen=granted, exact_alarm=granted, '
        'battery_unrestricted=denied';
    final body = feedbackBody(_vi, _diag());
    expect(body, isNot(contains(RegExp(r'(?<!\r)\n'))));
    expect(body, isNot(contains(RegExp(r'\r(?!\n)'))));
    final lines = body.split('\r\n');
    expect(lines.first, _vi.prompt);
    expect(lines.sublist(1, 5), everyElement(isEmpty));
    expect(lines[5], kFeedbackSeparator);
    expect(lines[6], _vi.diagHeader);
    expect(lines.sublist(7), [
      'App: NapStop 0.1.0 (1), prod',
      'OS: Android 15 (API 35)',
      'Device: Xiaomi 23078PND5G',
      'Language: app=system, device=vi-VN',
      permissions,
      'Engine: default',
    ]);
  });

  test('U12 only App and Language when the sources are missing', () {
    expect(
      diagnosticsLines(
        _diag(
          version: null,
          build: null,
          flavor: AppFlavor.dev,
          noDevice: true,
          noPermissions: true,
          paramsId: null,
          language: AppLanguage.en,
          locale: 'en-US',
        ),
      ),
      ['App: NapStop ?, dev', 'Language: app=en, device=en-US'],
    );
  });

  test('U13 no location, place, trip or Firebase words', () {
    final coordinate = RegExp(r'-?\d{1,3}\.\d{4,}');
    const banned = [
      'lat',
      'lng',
      'lon',
      'trip',
      'destination',
      'place',
      'firebase',
      'installation',
    ];
    for (final copy in [_vi, _en]) {
      for (final d in [
        _diag(),
        _diag(device: _ios(), permissions: iosPermissions()),
        _diag(language: AppLanguage.vi, paramsId: 'invalid'),
        _diag(
          device: androidDevice(),
          permissions: androidPermissions(),
          paramsId: '0a1b2c3d',
          language: AppLanguage.en,
          locale: 'en-GB',
        ),
      ]) {
        final text = '${feedbackSubject(copy, d)}\n${feedbackBody(copy, d)}';
        expect(text, isNot(contains(coordinate)));
        final lower = text.toLowerCase();
        for (final word in banned) {
          expect(lower, isNot(contains(word)), reason: word);
        }
      }
    }
  });
}

// T23 TP01–TP09: Places API (New) client with MockClient. No request ever
// leaves the test process.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/destination/data/places/places_client.dart';
import 'package:napstop/features/destination/data/places/places_models.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

const _key = 'test-key-K';
const _token = '0b9f7c1e-3a52-4d8e-9c1a-2f4b6d8e0a13';

MapsConfigMsg androidConfig({String? key = _key}) => MapsConfigMsg(
  apiKey: key,
  androidPackage: 'app.napstop.dev',
  androidCertSha1: 'A9993E364706816ABA3E25717850C26C9CD0D89D',
);

MapsConfigMsg iosConfig() =>
    MapsConfigMsg(apiKey: _key, iosBundleId: 'app.napstop');

http.Response json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const Map<String, Object> _sample = {
  'suggestions': [
    {
      'placePrediction': {
        'placeId': 'p1',
        'text': {'text': 'Bến xe Đức Long, Gia Lai'},
        'structuredFormat': {
          'mainText': {'text': 'Bến xe Đức Long'},
          'secondaryText': {'text': 'Gia Lai, Việt Nam'},
        },
      },
    },
    {
      'placePrediction': {
        'placeId': 'p2',
        'text': {'text': 'Đức Long Gia Lai'},
      },
    },
    {
      'placePrediction': {
        'placeId': 'p3',
        'text': {'text': ''},
        'structuredFormat': {
          'mainText': {'text': '  '},
        },
      },
    },
    {
      'queryPrediction': {
        'text': {'text': 'bến xe đức long'},
      },
    },
  ],
};

class _Recorder {
  final List<http.Request> requests = [];
  http.Response Function(http.Request r) reply = (_) => json(_sample);

  MockClient get client => MockClient((r) async {
    requests.add(r);
    return reply(r);
  });
}

void main() {
  late _Recorder rec;

  setUp(() => rec = _Recorder());

  PlacesClient client(MapsConfigMsg config, {String lang = 'vi'}) =>
      PlacesClient(client: rec.client, config: config, languageCode: lang);

  test('TP01 Android autocomplete request', () async {
    await client(androidConfig())
        .autocomplete('Bến xe Đức Long', sessionToken: _token);
    final r = rec.requests.single;
    expect(r.method, 'POST');
    expect(
      r.url.toString(),
      'https://places.googleapis.com/v1/places:autocomplete',
    );
    expect(r.headers['X-Goog-Api-Key'], _key);
    expect(r.headers['X-Android-Package'], 'app.napstop.dev');
    expect(
      r.headers['X-Android-Cert'],
      'A9993E364706816ABA3E25717850C26C9CD0D89D',
    );
    expect(
      r.headers['X-Goog-FieldMask'],
      'suggestions.placePrediction.placeId,'
      'suggestions.placePrediction.text,'
      'suggestions.placePrediction.structuredFormat',
    );
    expect(r.headers['Content-Type'], startsWith('application/json'));
    expect(r.headers.keys.where((k) => k.startsWith('X-Ios')), isEmpty);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body, {
      'input': 'Bến xe Đức Long',
      'sessionToken': _token,
      'languageCode': 'vi',
      'regionCode': 'vn',
      'includedRegionCodes': ['vn'],
    });
    for (final banned in ['locationBias', 'locationRestriction', 'origin']) {
      expect(body.containsKey(banned), isFalse, reason: banned);
    }
  });

  test('TP02 iOS headers, English', () async {
    await client(
      iosConfig(),
      lang: 'en',
    ).autocomplete('Hue', sessionToken: _token);
    final r = rec.requests.single;
    expect(r.headers['X-Ios-Bundle-Identifier'], 'app.napstop');
    expect(r.headers.keys.where((k) => k.startsWith('X-Android')), isEmpty);
    expect((jsonDecode(r.body) as Map)['languageCode'], 'en');
  });

  test('TP03 input trimmed and cut to 100 runes, no split surrogate', () async {
    final long = '  ${'Đồng Hới 😴 ' * 15}  ';
    await client(androidConfig()).autocomplete(long, sessionToken: _token);
    final input =
        (jsonDecode(rec.requests.single.body) as Map)['input'] as String;
    expect(input.runes.length, kMaxPlacesInputRunes);
    expect(input.startsWith('Đồng'), isTrue);
    expect(long.trim().startsWith(input), isTrue);
  });

  test('TP04 parse: placePrediction only, mainText fallback, max 5', () {
    final r = parseAutocomplete(jsonEncode(_sample));
    expect(r, const [
      PlacePrediction(
        placeId: 'p1',
        mainText: 'Bến xe Đức Long',
        secondaryText: 'Gia Lai, Việt Nam',
      ),
      PlacePrediction(placeId: 'p2', mainText: 'Đức Long Gia Lai'),
    ]);
    final many = {
      'suggestions': [
        for (var i = 0; i < 8; i++)
          {
            'placePrediction': {
              'placeId': 'id$i',
              'text': {'text': 'Place $i'},
            },
          },
      ],
    };
    expect(parseAutocomplete(jsonEncode(many)), hasLength(5));
    expect(parseAutocomplete('{}'), isEmpty);
    expect(
      () => parseAutocomplete('not json'),
      throwsA(isA<PlacesBadResponse>()),
    );
  });

  test('TP05 place details request', () async {
    rec.reply = (_) => json({
      'location': {'latitude': 16.05, 'longitude': 108.2},
    });
    await client(androidConfig()).location('ChIJ/abc', sessionToken: _token);
    final r = rec.requests.single;
    expect(r.method, 'GET');
    expect(
      r.url.toString(),
      'https://places.googleapis.com/v1/places/ChIJ%2Fabc'
      '?sessionToken=$_token&languageCode=vi',
    );
    expect(r.headers['X-Goog-FieldMask'], 'location');
    expect(r.headers['X-Goog-Api-Key'], _key);
    expect(r.headers['X-Android-Package'], 'app.napstop.dev');
  });

  test('TP06 location: value, missing, out of range', () async {
    final c = client(androidConfig());
    rec.reply = (_) => json({
      'location': {'latitude': 16.05, 'longitude': 108.2},
    });
    expect(
      await c.location('p', sessionToken: _token),
      const MapPoint(16.05, 108.2),
    );
    rec.reply = (_) => json({'id': 'p'});
    await expectLater(
      c.location('p', sessionToken: _token),
      throwsA(isA<PlacesBadResponse>()),
    );
    rec.reply = (_) => json({
      'location': {'latitude': 95, 'longitude': 108.2},
    });
    await expectLater(
      c.location('p', sessionToken: _token),
      throwsA(isA<PlacesBadResponse>()),
    );
  });

  test('TP07 HTTP status and network errors', () async {
    final c = client(androidConfig());
    for (final (status, matcher) in [
      (400, isA<PlacesDenied>().having((e) => e.status, 'status', 400)),
      (403, isA<PlacesDenied>().having((e) => e.status, 'status', 403)),
      (429, isA<PlacesQuotaExceeded>()),
      (500, isA<PlacesServerError>().having((e) => e.status, 'status', 500)),
      (503, isA<PlacesServerError>().having((e) => e.status, 'status', 503)),
    ]) {
      rec.reply = (_) => json({'error': 'x'}, status);
      await expectLater(
        c.autocomplete('abc', sessionToken: _token),
        throwsA(matcher),
        reason: '$status',
      );
    }
    rec.reply = (_) => throw const SocketException('offline');
    await expectLater(
      c.autocomplete('abc', sessionToken: _token),
      throwsA(isA<PlacesNetworkError>()),
    );
    rec.reply = (_) => throw http.ClientException('reset');
    await expectLater(
      c.location('p', sessionToken: _token),
      throwsA(isA<PlacesNetworkError>()),
    );
  });

  testWidgets('TP07 timeout after 8 s is a network error', (tester) async {
    // testWidgets runs in fake time: no real 8 s wait.
    final never = MockClient((_) => Completer<http.Response>().future);
    final c = PlacesClient(
      client: never,
      config: androidConfig(),
      languageCode: 'vi',
    );
    Object? error;
    unawaited(
      c
          .autocomplete('abc', sessionToken: _token)
          .then<void>((_) {}, onError: (Object e) => error = e),
    );
    await tester.pump(const Duration(seconds: 7));
    expect(error, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(error, isA<PlacesNetworkError>());
  });

  test('TP08 no key: PlacesNotConfigured, no request', () async {
    for (final key in [null, '', '  ']) {
      final c = client(androidConfig(key: key));
      expect(c.isConfigured, isFalse);
      await expectLater(
        c.autocomplete('abc', sessionToken: _token),
        throwsA(isA<PlacesNotConfigured>()),
      );
      await expectLater(
        c.location('p', sessionToken: _token),
        throwsA(isA<PlacesNotConfigured>()),
      );
    }
    expect(rec.requests, isEmpty);
  });

  test('TP09 toString never prints input, key, URL or place id', () {
    const values = <Object>[
      PlacesNotConfigured(),
      PlacesNetworkError(),
      PlacesDenied(403),
      PlacesQuotaExceeded(),
      PlacesServerError(503),
      PlacesBadResponse(),
      PlacePrediction(
        placeId: 'ChIJsecret',
        mainText: 'Bến xe Đức Long',
        secondaryText: 'Gia Lai',
      ),
    ];
    for (final v in values) {
      final text = v.toString();
      for (final secret in [
        'ChIJsecret',
        'Đức Long',
        'Gia Lai',
        _key,
        'googleapis',
        'http',
      ]) {
        expect(text.contains(secret), isFalse, reason: '$secret in $text');
      }
    }
    expect(const PlacesDenied(403).toString(), 'PlacesDenied(403)');
  });
}

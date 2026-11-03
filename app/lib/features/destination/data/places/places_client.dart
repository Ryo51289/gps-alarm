/// Places API (New) over REST (T23 §8): Autocomplete with a session token,
/// then Place Details with the `location` field only (Essentials SKU).
///
/// PRIVACY (PRD §5): only what the user typed goes to Google, never the
/// user's position or any area around it. Never log the
/// input, a URL, a body, a response or the key. No caching.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/destination/data/places/places_models.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

const String _host = 'places.googleapis.com';

const String _autocompleteFieldMask =
    'suggestions.placePrediction.placeId,'
    'suggestions.placePrediction.text,'
    'suggestions.placePrediction.structuredFormat';

/// Place Details field mask: Essentials only (T23 D6). Required by the API.
const String _detailsFieldMask = 'location';

/// Calls the Places API (New). Depends only on [http.Client], so tests use
/// `MockClient`.
final class PlacesClient {
  new({
    required this._client,
    required this._config,
    required this._languageCode,
    this._timeout = const Duration(seconds: 8),
  });

  final http.Client _client;
  final MapsConfigMsg _config;
  final String _languageCode;
  final Duration _timeout;

  /// Whether this build has a key.
  bool get isConfigured => _apiKey != null;

  String? get _apiKey {
    final key = _config.apiKey;
    return key == null || key.trim().isEmpty ? null : key;
  }

  /// Up to 5 suggestions for [input] (trimmed, at most
  /// [kMaxPlacesInputRunes] runes), restricted to Vietnam.
  Future<List<PlacePrediction>> autocomplete(
    String input, {
    required String sessionToken,
  }) async {
    final key = _requireKey();
    final body = jsonEncode({
      'input': _cut(input.trim()),
      'sessionToken': sessionToken,
      'languageCode': _languageCode,
      'regionCode': 'vn',
      'includedRegionCodes': ['vn'],
    });
    final response = await _send(
      () => _client.post(
        Uri.https(_host, '/v1/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          ..._headers(key, _autocompleteFieldMask),
        },
        body: body,
      ),
    );
    return parseAutocomplete(response);
  }

  /// Coordinates of [placeId]; ends the session of [sessionToken].
  Future<MapPoint> location(
    String placeId, {
    required String sessionToken,
  }) async {
    final key = _requireKey();
    final uri = Uri(
      scheme: 'https',
      host: _host,
      pathSegments: ['v1', 'places', placeId],
      queryParameters: {
        'sessionToken': sessionToken,
        'languageCode': _languageCode,
      },
    );
    final response = await _send(
      () => _client.get(uri, headers: _headers(key, _detailsFieldMask)),
    );
    return parsePlaceLocation(response);
  }

  String _requireKey() {
    final key = _apiKey;
    if (key == null) {
      throw const PlacesNotConfigured();
    }
    return key;
  }

  /// Key, field mask and the app restriction headers that have a value.
  Map<String, String> _headers(String key, String fieldMask) {
    final package = _config.androidPackage;
    final cert = _config.androidCertSha1;
    final bundle = _config.iosBundleId;
    return {
      'X-Goog-Api-Key': key,
      'X-Goog-FieldMask': fieldMask,
      if (package != null && package.isNotEmpty) 'X-Android-Package': package,
      if (cert != null && cert.isNotEmpty) 'X-Android-Cert': cert,
      if (bundle != null && bundle.isNotEmpty)
        'X-Ios-Bundle-Identifier': bundle,
    };
  }

  /// The response body of a 200; every failure as a [PlacesException].
  Future<String> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw const PlacesNetworkError();
    } on SocketException {
      throw const PlacesNetworkError();
    } on http.ClientException {
      throw const PlacesNetworkError();
    }
    final status = response.statusCode;
    if (status == 200) {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    }
    if (status == 400 || status == 401 || status == 403) {
      throw PlacesDenied(status);
    }
    if (status == 429) {
      throw const PlacesQuotaExceeded();
    }
    throw PlacesServerError(status);
  }
}

String _cut(String input) {
  final runes = input.runes;
  return runes.length > kMaxPlacesInputRunes
      ? String.fromCharCodes(runes.take(kMaxPlacesInputRunes))
      : input;
}

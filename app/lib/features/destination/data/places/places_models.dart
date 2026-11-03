/// Places API (New) results and errors (T23 §8). Pure Dart.
///
/// PRIVACY: no `toString` here prints user input, a place id, a URL or the
/// API key.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

/// Most suggestions kept from one Autocomplete response.
const int kMaxPlacePredictions = 5;

/// One Autocomplete suggestion.
@immutable
final class PlacePrediction {
  const new({
    required this.placeId,
    required this.mainText,
    this.secondaryText,
  });

  final String placeId;

  /// Name shown as the row title and used as the destination name.
  final String mainText;

  /// Address line, shown as subtitle and kept as the destination detail.
  final String? secondaryText;

  @override
  bool operator ==(Object other) =>
      other is PlacePrediction &&
      other.placeId == placeId &&
      other.mainText == mainText &&
      other.secondaryText == secondaryText;

  @override
  int get hashCode => Object.hash(placeId, mainText, secondaryText);

  @override
  String toString() => 'PlacePrediction';
}

/// Why a Places call failed. `toString` gives the class name and the HTTP
/// status only.
sealed class PlacesException implements Exception {
  const new();
}

/// No API key in this build.
final class PlacesNotConfigured extends PlacesException {
  const new();

  @override
  String toString() => 'PlacesNotConfigured';
}

/// No connection, socket error or timeout.
final class PlacesNetworkError extends PlacesException {
  const new();

  @override
  String toString() => 'PlacesNetworkError';
}

/// HTTP 400, 401 or 403 (bad key, key restrictions, API not enabled).
final class PlacesDenied extends PlacesException {
  const new(this.status);

  final int status;

  @override
  String toString() => 'PlacesDenied($status)';
}

/// HTTP 429.
final class PlacesQuotaExceeded extends PlacesException {
  const new();

  @override
  String toString() => 'PlacesQuotaExceeded';
}

/// HTTP 5xx or any other unexpected status.
final class PlacesServerError extends PlacesException {
  const new(this.status);

  final int status;

  @override
  String toString() => 'PlacesServerError($status)';
}

/// Unreadable JSON, missing location or coordinates out of range.
final class PlacesBadResponse extends PlacesException {
  const new();

  @override
  String toString() => 'PlacesBadResponse';
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    throw const PlacesBadResponse();
  }
}

String? _text(Object? node) {
  if (node is Map<String, Object?>) {
    final text = node['text'];
    if (text is String && text.trim().isNotEmpty) {
      return text.trim();
    }
  }
  return null;
}

/// Suggestions of an Autocomplete response: only `placePrediction` items
/// with a place id and a non-empty name (`structuredFormat.mainText`, else
/// `text`), at most [kMaxPlacePredictions]. No `suggestions` → empty.
List<PlacePrediction> parseAutocomplete(String body) {
  final root = _decode(body);
  if (root is! Map<String, Object?>) {
    throw const PlacesBadResponse();
  }
  final suggestions = root['suggestions'];
  if (suggestions == null) {
    return const [];
  }
  if (suggestions is! List<Object?>) {
    throw const PlacesBadResponse();
  }
  final out = <PlacePrediction>[];
  for (final s in suggestions) {
    if (out.length == kMaxPlacePredictions) {
      break;
    }
    if (s is! Map<String, Object?>) {
      continue;
    }
    final p = s['placePrediction'];
    if (p is! Map<String, Object?>) {
      continue;
    }
    final placeId = p['placeId'];
    if (placeId is! String || placeId.isEmpty) {
      continue;
    }
    final structured = p['structuredFormat'];
    String? main;
    String? secondary;
    if (structured is Map<String, Object?>) {
      main = _text(structured['mainText']);
      secondary = _text(structured['secondaryText']);
    }
    main ??= _text(p['text']);
    if (main == null) {
      continue;
    }
    out.add(
      PlacePrediction(
        placeId: placeId,
        mainText: main,
        secondaryText: secondary,
      ),
    );
  }
  return List.unmodifiable(out);
}

/// `location` of a Place Details response; finite and in range, else
/// [PlacesBadResponse].
MapPoint parsePlaceLocation(String body) {
  final root = _decode(body);
  if (root is! Map<String, Object?>) {
    throw const PlacesBadResponse();
  }
  final location = root['location'];
  if (location is! Map<String, Object?>) {
    throw const PlacesBadResponse();
  }
  final lat = location['latitude'];
  final lng = location['longitude'];
  if (lat is! num || lng is! num) {
    throw const PlacesBadResponse();
  }
  final la = lat.toDouble();
  final ln = lng.toDouble();
  if (!la.isFinite || !ln.isFinite || la.abs() > 90 || ln < -180 || ln >= 180) {
    throw const PlacesBadResponse();
  }
  return MapPoint(la, ln);
}

/// Wire format v1 of the address search channel `app.napstop/address_search`
/// (T23.5 §3; `StandardMessageCodec`, no Pigeon: T14 D5). Pure Dart. The
/// Swift side (`AddressSearchWire.swift`) parses the same format; both are
/// checked against `fixtures/address_search_wire/cases.json`.
///
/// PRIVACY: nothing here logs, and no `toString` prints a typed text, a
/// suggestion or coordinates.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/features/destination/domain/address_search.dart';

const String kAddressSearchChannel = 'app.napstop/address_search';

const int kAddressWireVersion = 1;

/// `ok`, `superseded`, `network`, `throttled`, `failed`, `timeout` come with
/// `complete`; `stale` and `notFound` only with `resolve`.
enum AddressStatus {
  ok,
  superseded,
  network,
  throttled,
  failed,
  timeout,
  stale,
  notFound,
}

const Set<AddressStatus> _completeStatuses = {
  AddressStatus.ok,
  AddressStatus.superseded,
  AddressStatus.network,
  AddressStatus.throttled,
  AddressStatus.failed,
  AddressStatus.timeout,
};

AddressStatus? _status(Object? raw) {
  if (raw is! String) {
    return null;
  }
  for (final s in AddressStatus.values) {
    if (s.name == raw) {
      return s;
    }
  }
  return null;
}

/// Answer to `complete`.
@immutable
final class CompleteReply {
  const new({required this.gen, required this.status, this.items = const []});

  final int gen;
  final AddressStatus status;

  /// Only with [AddressStatus.ok].
  final List<AddressSuggestion> items;

  /// PRIVACY: no suggestion text.
  @override
  String toString() => 'CompleteReply(${status.name}, ${items.length})';
}

/// Answer to `resolve`.
@immutable
final class ResolveReply {
  const new({required this.status, this.point, this.country});

  final AddressStatus status;

  /// Only with [AddressStatus.ok].
  final MapPoint? point;

  /// ISO country code when Apple gave one.
  final String? country;

  /// PRIVACY: no coordinates.
  @override
  String toString() => 'ResolveReply(${status.name})';
}

Map<String, Object?> encodeComplete({
  required int gen,
  required String query,
  required MapBounds region,
}) => {
  'v': kAddressWireVersion,
  'gen': gen,
  'query': query,
  'region': region.toWire(),
};

Map<String, Object?> encodeResolve({required int gen, required int index}) => {
  'v': kAddressWireVersion,
  'gen': gen,
  'index': index,
};

/// null when [raw] is malformed. Items beyond [kMaxAddressItems] are cut;
/// an item that is not `{t: String, s: String}` makes the reply malformed.
CompleteReply? decodeCompleteReply(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final gen = raw['gen'];
  final status = _status(raw['status']);
  if (gen is! int || status == null || !_completeStatuses.contains(status)) {
    return null;
  }
  if (status != AddressStatus.ok) {
    return CompleteReply(gen: gen, status: status);
  }
  final items = raw['items'];
  if (items is! List) {
    return null;
  }
  final out = <AddressSuggestion>[];
  for (final item in items.take(kMaxAddressItems)) {
    if (item is! Map) {
      return null;
    }
    final t = item['t'];
    final s = item['s'];
    if (t is! String || s is! String) {
      return null;
    }
    out.add(AddressSuggestion(title: t, subtitle: s));
  }
  return CompleteReply(gen: gen, status: status, items: List.unmodifiable(out));
}

/// null when [raw] is malformed, or `ok` without a valid `lat`/`lng`.
ResolveReply? decodeResolveReply(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final status = _status(raw['status']);
  if (status == null) {
    return null;
  }
  if (status != AddressStatus.ok) {
    return ResolveReply(status: status);
  }
  final lat = raw['lat'];
  final lng = raw['lng'];
  final country = raw['country'];
  if (lat is! num ||
      lng is! num ||
      !isValidLatLng(lat.toDouble(), lng.toDouble())) {
    return null;
  }
  if (country != null && country is! String) {
    return null;
  }
  return ResolveReply(
    status: status,
    point: MapPoint(lat.toDouble(), lng.toDouble()),
    country: country as String?,
  );
}

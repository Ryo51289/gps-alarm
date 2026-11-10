/// Dart end of the address search channel (T23.5 §4.2, D1, D2): a request →
/// reply `MethodChannel`, `StandardMessageCodec`.
///
/// PRIVACY: nothing here logs. Only the typed text and the Vietnam box go to
/// the native side; never the user's location (D11).
library;

import 'package:flutter/services.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';

/// The native side answered with a message that does not parse.
final class AddressSearchProtocolException implements Exception {
  const new();

  @override
  String toString() => 'AddressSearchProtocolException';
}

abstract interface class AddressSearchClient {
  /// Suggestions for [query] inside [kVietnamBounds]; [gen] comes back in the
  /// reply.
  Future<CompleteReply> complete({required int gen, required String query});

  /// Location of suggestion [index] of the answer [gen].
  Future<ResolveReply> resolve({required int gen, required int index});

  /// Cancels the running completer and search; waiting calls get
  /// `superseded`.
  Future<void> cancel();
}

final class MethodChannelAddressSearchClient implements AddressSearchClient {
  const new({this.channel = const MethodChannel(kAddressSearchChannel)});

  final MethodChannel channel;

  @override
  Future<CompleteReply> complete({
    required int gen,
    required String query,
  }) async {
    final raw = await channel.invokeMethod<Object?>(
      'complete',
      encodeComplete(gen: gen, query: query, region: kVietnamBounds),
    );
    final reply = decodeCompleteReply(raw);
    if (reply == null) {
      throw const AddressSearchProtocolException();
    }
    return reply;
  }

  @override
  Future<ResolveReply> resolve({required int gen, required int index}) async {
    final raw = await channel.invokeMethod<Object?>(
      'resolve',
      encodeResolve(gen: gen, index: index),
    );
    final reply = decodeResolveReply(raw);
    if (reply == null) {
      throw const AddressSearchProtocolException();
    }
    return reply;
  }

  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}

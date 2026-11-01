/// HTTP transport for `fetch` (spec T24 §6). Injected so tests never touch
/// the network.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Response of a [Transport] call.
final class TransportResponse {
  const new({required this.status, required this.bytes});

  final int status;

  /// Body bytes. May be truncated to `maxResponseBytes + 1` by the default
  /// transport, so callers can still detect an oversized response.
  final List<int> bytes;
}

/// POSTs [body] to [endpoint] with [headers].
typedef Transport = Future<TransportResponse> Function(
  Uri endpoint,
  Map<String, String> headers,
  String body,
);

/// Responses larger than this are refused (spec §2.1).
const int kMaxResponseBytes = 20 * 1024 * 1024;

/// Query `[timeout:300]` plus margin for queueing and transfer.
const Duration kRequestTimeout = Duration(seconds: 420);

/// Default [Transport] built on `dart:io` [HttpClient]. Single attempt, no
/// retry.
Future<TransportResponse> httpTransport(
  Uri endpoint,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 5);
  // One deadline for the whole exchange (headers and body).
  final clock = Stopwatch()..start();
  try {
    final request = await client.postUrl(endpoint);
    headers.forEach(request.headers.set);
    request.add(utf8.encode(body));
    final response = await request.close().timeout(kRequestTimeout);
    final bytes = <int>[];
    final done = Completer<void>();
    late final StreamSubscription<List<int>> sub;
    sub = response.listen(
      (chunk) {
        bytes.addAll(chunk);
        if (bytes.length > kMaxResponseBytes) {
          unawaited(sub.cancel());
          if (!done.isCompleted) {
            done.complete();
          }
        }
      },
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) {
          done.completeError(e, s);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      cancelOnError: true,
    );
    await done.future.timeout(kRequestTimeout - clock.elapsed);
    return TransportResponse(status: response.statusCode, bytes: bytes);
  } finally {
    client.close(force: true);
  }
}

// Fake iOS platform-view host for the MapKit view (T23.3). Answers
// `SystemChannels.platform_views` so a `UiKitView` gets created in widget
// tests, decodes its creation params and records what Dart sends on the
// view's own channel. Not a test file.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/map/map_wire.dart';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

class FakeNapMapPlatform {
  /// View ids, in creation order.
  final List<int> created = [];
  final List<int> disposed = [];

  /// Decoded `creationParams` per view.
  final Map<int, Map<Object?, Object?>> params = {};

  /// Calls Dart sent on `app.napstop/nap_map/<id>`.
  final Map<int, List<MethodCall>> calls = {};

  /// Installs the fake; removed at tear-down.
  void install() {
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments;
      switch (call.method) {
        case 'create':
          final m = args! as Map<Object?, Object?>;
          final id = m['id']! as int;
          if (m['viewType'] != kNapMapViewType) {
            return null;
          }
          created.add(id);
          final bytes = m['params'] as Uint8List?;
          params[id] = bytes == null
              ? const {}
              : const StandardMessageCodec().decodeMessage(
                      ByteData.sublistView(bytes),
                    )!
                    as Map<Object?, Object?>;
          final list = calls[id] = [];
          final channel = MethodChannel(napMapChannelName(id));
          _messenger.setMockMethodCallHandler(channel, (c) async {
            list.add(c);
            return null;
          });
        case 'dispose':
          final id = args is int ? args : (args! as Map)['id']! as int;
          disposed.add(id);
          _messenger.setMockMethodCallHandler(
            MethodChannel(napMapChannelName(id)),
            null,
          );
      }
      return null;
    });
    addTearDown(() {
      _messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final id in created) {
        _messenger.setMockMethodCallHandler(
          MethodChannel(napMapChannelName(id)),
          null,
        );
      }
    });
  }

  int get lastId => created.last;

  List<MethodCall> callsOf(String method, [int? id]) => [
    for (final c in calls[id ?? lastId] ?? const <MethodCall>[])
      if (c.method == method) c,
  ];

  /// The last `setState` payload sent to view [id] (default: the last one).
  Map<Object?, Object?>? lastState([int? id]) {
    final list = callsOf('setState', id);
    return list.isEmpty ? null : list.last.arguments as Map<Object?, Object?>;
  }

  /// Native → Dart event on view [id] (default: the last one).
  Future<void> emit(String method, [Object? args, int? id]) =>
      _messenger.handlePlatformMessage(
        napMapChannelName(id ?? lastId),
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
}

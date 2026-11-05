import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/features/history/data/history_sync.dart';

/// App-wide work tied to the app's life (T28 §3.2, §4.1), placed in
/// `MaterialApp.router(builder:)`:
/// - history sync on start, on resume and on each `TripEndedMsg` (the trip
///   updates are only followed while the app is visible: no decoding of every
///   step in the background, an end there is picked up at the next resume);
/// - the app language pushed to the native strings and to the crash `locale`
///   key, at start and on every change.
class AppBackgroundTasks extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppBackgroundTasks> createState() => _AppBackgroundTasksState();
}

class _AppBackgroundTasksState extends ConsumerState<AppBackgroundTasks> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<TripUpdateMsg>? _updates;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _sync();
        _follow();
      },
      onHide: _unfollow,
    );
    _follow();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sync();
      }
    });
    ref.listenManual(
      appSettingsProvider.select((s) => s.display.language),
      (_, language) => _pushLocale(language),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_updates?.cancel());
    _updates = null;
    super.dispose();
  }

  void _sync() => unawaited(ref.read(historySyncProvider).sync());

  void _follow() {
    _updates ??= ref.read(coreBridgeProvider).updates.listen(
      (update) {
        if (update is TripEndedMsg && mounted) {
          _sync();
        }
      },
      // A broken update channel never breaks the app.
      onError: (Object _) {},
    );
  }

  void _unfollow() {
    final s = _updates;
    _updates = null;
    unawaited(s?.cancel());
  }

  /// Best effort: no native side or a failing call keeps the previous
  /// language there; the next app start pushes again.
  void _pushLocale(AppLanguage language) {
    final tag = DisplayPreferences(
      language: language,
      theme: AppThemeChoice.system,
    ).nativeTag;
    unawaited(
      ref.read(coreBridgeProvider).setAppLocale(tag).catchError((Object _) {}),
    );
    final code =
        tag ?? WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    ref
        .read(telemetryProvider)
        .crash
        .setKey(CrashKey.locale, crashLocaleOf(code));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

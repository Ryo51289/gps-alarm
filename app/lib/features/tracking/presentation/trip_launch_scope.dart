import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';

/// Path of the top route, pushed routes included (`/overshoot` for
/// `/overshoot?trip=…`); null before the first route is set.
String? topRoutePath(GoRouter router) {
  if (router.routerDelegate.currentConfiguration.isEmpty) {
    return null;
  }
  return router.state.uri.path;
}

/// Opens screen 4 when the app starts or comes back with a trip running
/// (T26 D12, §6.1), **only** from screen 1: never over screen 0/2/3/9 or
/// over T27's `/alarm` and `/overshoot` (checked again after the await,
/// T27 may navigate meanwhile). Errors count as "no trip". Never touches
/// the history (D15).
class TripLaunchScope extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<TripLaunchScope> createState() => _TripLaunchScopeState();
}

class _TripLaunchScopeState extends ConsumerState<TripLaunchScope> {
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_check()));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy || !mounted) {
      return;
    }
    _busy = true;
    try {
      final router = ref.read(appRouterProvider);
      if (topRoutePath(router) != AppRoutes.home) {
        return;
      }
      final bridge = ref.read(coreBridgeProvider);
      ActiveTripMsg? trip;
      try {
        trip = await bridge.currentTrip();
      } on Object {
        trip = null;
      }
      // Again after the await: T27 may have opened /overshoot or /alarm.
      if (!mounted ||
          trip == null ||
          trip.state.phase == TripPhaseMsg.ended ||
          topRoutePath(router) != AppRoutes.home) {
        return;
      }
      router.go(AppRoutes.tracking);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

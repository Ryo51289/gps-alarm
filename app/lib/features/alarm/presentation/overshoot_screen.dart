import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm/data/maps_launcher.dart';
import 'package:napstop/features/alarm/domain/alarm_copy.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';
import 'package:napstop/features/alarm/presentation/widgets/alarm_glow.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 8 after the alarm was dismissed (T27 §7): "Đã qua …", the alarm
/// is off and tracking stopped, Google Maps directions back (D8). Opened
/// with `go` (D9); Back and "Về trang chủ" go to screen 1. With
/// `open=1` Maps opens once by itself for a recent trip (D12).
///
/// PRIVACY: never logs the destination, its coordinates or the URL (D14).
class OvershootScreen extends ConsumerStatefulWidget {
  const new({required this.args, super.key});

  final OvershootArgs args;

  @override
  ConsumerState<OvershootScreen> createState() => _OvershootScreenState();
}

class _OvershootScreenState extends ConsumerState<OvershootScreen> {
  TripRecord? _record;
  Uri? _uri;
  bool _loaded = false;
  bool _autoOpened = false;
  bool _opening = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    TripRecord? record;
    try {
      record = await ref.read(tripsRepositoryProvider).byId(widget.args.tripId);
    } on Object catch (error, stack) {
      reportNonFatal('overshoot.byId', error, stack);
      record = null;
    }
    if (!mounted) {
      return;
    }
    final uri = record == null
        ? null
        : routeBackUri(record.destination.lat, record.destination.lng);
    setState(() {
      _record = record;
      _uri = uri;
      _loaded = true;
    });
    if (widget.args.autoOpen &&
        !_autoOpened &&
        uri != null &&
        mayAutoOpen(record, ref.read(clockProvider)())) {
      _autoOpened = true;
      unawaited(_openMaps());
    }
  }

  Future<void> _openMaps() async {
    final uri = _uri;
    if (_opening || uri == null) {
      return;
    }
    _opening = true;
    ref
        .read(telemetryProvider)
        .analytics
        .log(
          OvershootActionEvent(
            action: OvershootActionTag.openMaps,
            simulated: _record?.simulated ?? false,
          ),
        );
    var ok = false;
    try {
      ok = await ref.read(mapsLauncherProvider)(uri);
    } on Object catch (error, stack) {
      // Type only: the error text may quote the URL (coordinates).
      reportNonFatal('overshoot.openMaps', error, stack);
      ok = false;
    }
    _opening = false;
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).overshootOpenMapsFailed),
            persist: false,
          ),
        );
    }
  }

  void _goHome() {
    if (_left) {
      return;
    }
    _left = true;
    ref
        .read(telemetryProvider)
        .analytics
        .log(
          OvershootActionEvent(
            action: OvershootActionTag.dismiss,
            simulated: _record?.simulated ?? false,
          ),
        );
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Theme(
      data: NapThemes.alarm(),
      child: PopScope<Object?>(
        // The trip is over: Back goes to screen 1, not to an older screen.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _goHome();
          }
        },
        child: Semantics(
          namesRoute: true,
          explicitChildNodes: true,
          label: l.appScreenOvershootTitle,
          child: Builder(builder: (context) => _body(context, l)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final c = context.napColors;
    final text = context.napText;
    final record = _record;
    final pastM = widget.args.pastM;
    final title = record?.destination.name ?? l.overshootPastUnknown;
    final pastLine = pastM != null
        ? alarmPastText(l, pastM)
        : record != null
        ? l.overshootPastUnknown
        : null;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: NapSpace.alarmPage,
            vertical: NapSpace.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: NapSpace.s16),
              Center(
                child: AlarmGlow(
                  color: c.overshootAccent,
                  icon: Icons.u_turn_left,
                  iconColor: c.onAlarmAccent,
                  pulse: false,
                ),
              ),
              const SizedBox(height: NapSpace.s24),
              Text(
                l.alarmOverlineOvershoot.toUpperCase(),
                textAlign: TextAlign.center,
                style: context
                    .napStyle(NapTypography.alarmOverline)
                    .copyWith(color: c.overshootLabel),
              ),
              const SizedBox(height: NapSpace.s12),
              // Nothing until the history row is read (no flash of the
              // "unknown" title).
              if (_loaded) ...[
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: text.headlineLarge,
                  ),
                ),
                if (pastLine != null) ...[
                  const SizedBox(height: NapSpace.s8),
                  Text(
                    pastLine,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: c.textSecondary),
                  ),
                ],
                const SizedBox(height: NapSpace.s24),
                NapListGroup(
                  bordered: false,
                  children: [
                    _Confirmation(l.overshootAlarmOff),
                    _Confirmation(l.overshootTrackingStopped),
                  ],
                ),
                if (record?.simulated ?? false) ...[
                  const SizedBox(height: NapSpace.s12),
                  Text(
                    l.overshootSimulatedNote,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                ],
                const SizedBox(height: NapSpace.s32),
                if (_uri != null) ...[
                  NapButton(
                    label: l.overshootRouteBack,
                    icon: Icons.directions_outlined,
                    onPressed: () => unawaited(_openMaps()),
                  ),
                  const SizedBox(height: NapSpace.s8),
                  Text(
                    l.overshootRouteBackHint,
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: NapSpace.s12),
                ],
                NapButton(
                  label: l.overshootGoHome,
                  variant: NapButtonVariant.text,
                  onPressed: _goHome,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "✓ Đã tắt báo thức" row.
class _Confirmation extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => NapListRow(
    title: label,
    titleWeight: NapRowTitle.regular,
    leading: ExcludeSemantics(
      child: Icon(Icons.check_circle_rounded, color: context.napColors.success),
    ),
  );
}

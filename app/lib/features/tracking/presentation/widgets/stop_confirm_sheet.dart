import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Dừng theo dõi" confirmation (T26 D14): stopping cannot be undone.
/// Resolves to true when the user confirmed.
Future<bool> showStopConfirmSheet(
  BuildContext context, {
  required String destination,
}) async {
  final stop = await showNapSheet<bool>(
    context: context,
    builder: (context) => StopConfirmSheet(destination: destination),
  );
  return stop ?? false;
}

/// Closes by itself (answer: no) once the trip is over, e.g. it was ended
/// on the alarm screen meanwhile (review T26 #5).
class StopConfirmSheet extends ConsumerStatefulWidget {
  const new({required this.destination, super.key});

  final String destination;

  @override
  ConsumerState<StopConfirmSheet> createState() => _StopConfirmSheetState();
}

class _StopConfirmSheetState extends ConsumerState<StopConfirmSheet> {
  bool _closed = false;

  void _close({required bool stop}) {
    if (_closed || !mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) {
      return;
    }
    _closed = true;
    if (route.isCurrent) {
      Navigator.of(context).pop(stop);
    } else {
      Navigator.of(context).removeRoute(route, stop);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(trackedTripProvider, (_, next) {
      final status = next.value;
      if (status is TrackingEnded || status is TrackingNone) {
        _close(stop: false);
      }
    });
    final l = AppLocalizations.of(context);
    return NapSheetBody(
      title: l.trackingStopConfirmTitle,
      subtitle: l.trackingStopConfirmBody(widget.destination),
      primaryAction: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s10,
        children: [
          NapButton(
            label: l.trackingStop,
            variant: NapButtonVariant.danger,
            onPressed: () => _close(stop: true),
          ),
          NapButton(
            label: l.trackingStopConfirmNo,
            variant: NapButtonVariant.secondary,
            onPressed: () => _close(stop: false),
          ),
        ],
      ),
      children: const [],
    );
  }
}

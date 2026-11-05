import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Display name of a bundled trace (T28 D14); unknown id → null (the caller
/// shows the destination name or the id).
String? simTraceTitle(AppLocalizations l, String id) => switch (id) {
  SimTraces.trainHnDh => l.simTraceTrainHnDh,
  SimTraces.coachMdTb => l.simTraceCoachMdTb,
  SimTraces.busHnBrt01 => l.simTraceBusHnBrt01,
  SimTraces.coachDnLangcoTunnel => l.simTraceCoachDnLangcoTunnel,
  SimTraces.coachGbPhulyOvershoot => l.simTraceCoachGbPhulyOvershoot,
  SimTraces.busHnBrt01Noisy => l.simTraceBusHnBrt01Noisy,
  _ => null,
};

/// "45 giây", "9 phút 23 giây", "9 giờ 23 phút" (seconds dropped from an
/// hour on).
String formatSimDuration(AppLocalizations l, Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (total < 60) {
    return l.simDurationSeconds(total);
  }
  if (total < 3600) {
    return l.simDurationMinutes(total ~/ 60, total % 60);
  }
  return l.simDurationHours(total ~/ 3600, (total % 3600) ~/ 60);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/features/simulation/data/sim_providers.dart';
import 'package:napstop/features/simulation/domain/sim_launch.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/features/simulation/presentation/sim_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// What the user picked in the simulation sheet.
typedef SimSelection = ({SimTrace trace, SimSpeed speed});

/// The hidden demo sheet (T28 §5): a bundled trace and a speed. Null when
/// dismissed. Only relative durations are shown (T18 D14).
Future<SimSelection?> showSimulationSheet(BuildContext context) =>
    showNapSheet<SimSelection>(
      context: context,
      builder: (_) => const SimulationSheet(),
    );

class SimulationSheet extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SimulationSheet> createState() => _SimulationSheetState();
}

class _SimulationSheetState extends ConsumerState<SimulationSheet> {
  String? _traceId;
  SimSpeed _speed = kDefaultSimSpeed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final catalog = ref.watch(simTraceCatalogProvider);
    final traces = catalog.value?.traces ?? const <SimTrace>[];
    final selected = traces.where((t) => t.id == _traceId).firstOrNull;
    final secondary = context.napText.bodyMedium!.copyWith(
      color: context.napColors.textSecondary,
    );
    return NapSheetBody(
      title: l.simSheetTitle,
      subtitle: l.simSheetHint,
      primaryAction: NapButton(
        label: l.simStart,
        onPressed: selected == null
            ? null
            : () =>
                  Navigator.of(context)
                      .pop<SimSelection>((trace: selected, speed: _speed)),
      ),
      children: [
        if (catalog.hasError)
          Text(l.simCatalogError, style: secondary)
        else if (catalog.isLoading && !catalog.hasValue)
          const Center(child: CircularProgressIndicator())
        else if (traces.isEmpty)
          Text(l.simCatalogEmpty, style: secondary)
        else
          NapListGroup(
            children: [
              for (final t in traces)
                NapListRow(
                  title: simTraceTitle(l, t.id) ?? t.destination.name ?? t.id,
                  subtitle: l.simTraceSubtitle(
                    l.vehicleLabel(t.vehicle) ?? '',
                    formatSimDuration(l, simArrivalAfter(t, _speed)),
                  ),
                  titleWeight: NapRowTitle.regular,
                  semanticsChecked: t.id == _traceId,
                  trailing: NapRadioIndicator(selected: t.id == _traceId),
                  onTap: () => setState(() => _traceId = t.id),
                ),
            ],
          ),
        NapSectionHeader(l.simSpeedLabel),
        NapSegmentedControl<SimSpeed>(
          semanticLabel: l.simSpeedLabel,
          segments: [
            for (final s in SimSpeed.values)
              NapSegment(value: s, label: l.simSpeedValue(s.factor)),
          ],
          selected: _speed,
          onChanged: (s) => setState(() => _speed = s),
        ),
      ],
    );
  }
}

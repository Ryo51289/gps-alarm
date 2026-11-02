import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/home/domain/greeting.dart';
import 'package:napstop/features/home/presentation/home_providers.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/features/home/presentation/widgets/active_trip_card.dart';
import 'package:napstop/features/home/presentation/widgets/readiness_card.dart';
import 'package:napstop/features/home/presentation/widgets/recent_trips_section.dart';
import 'package:napstop/features/home/presentation/widgets/saved_place_sheet.dart';
import 'package:napstop/features/home/presentation/widgets/saved_places_grid.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 1 "Trang chủ" (T22 §9).
class HomeScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Permissions, volume or DND may have changed while away.
    _lifecycle = AppLifecycleListener(onResume: _refreshReadiness);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refreshReadiness() {
    if (ref.read(deviceInfoProvider).hasError) {
      ref.invalidate(deviceInfoProvider);
    }
    ref.invalidate(readinessProvider);
  }

  bool get _tripRunning => ref.read(activeTripProvider).value != null;

  void _showSnack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      // persist: false: snack bars with an action hide by themselves too.
      ..showSnackBar(
        SnackBar(content: Text(text), action: action, persist: false),
      );
  }

  /// Screen 3 with [draft], unless a trip is running.
  void _openDraft(TripDraft draft) {
    if (_tripRunning) {
      final l = AppLocalizations.of(context);
      _showSnack(
        l.homeActiveTripBusy,
        action: SnackBarAction(
          label: l.homeActiveTripOpen,
          onPressed: _openTracking,
        ),
      );
      return;
    }
    // T29: destination_selected (source, kind) is logged here.
    unawaited(context.openAlarmSettings(draft));
  }

  void _openTracking() => context.openTracking();

  void _onSlotTap(SavedPlaceSlot slot, SavedPlace? place) {
    if (place == null) {
      unawaited(_pickInto(slot));
    } else {
      _openDraft(TripDraft.fromSavedPlace(place));
    }
  }

  /// Screen 2 as a picker; the result goes into [slot].
  Future<void> _pickInto(SavedPlaceSlot slot) async {
    final destination = await ref.read(destinationPickerProvider)(context);
    if (destination == null || !mounted) {
      return;
    }
    final failed = AppLocalizations.of(context).homeSaveFailed;
    try {
      await ref.read(savedPlacesRepositoryProvider).upsert(slot, destination);
    } on Object {
      if (mounted) {
        _showSnack(failed);
      }
    }
  }

  Future<void> _onSlotLongPress(SavedPlace place) async {
    final action = await showSavedPlaceSheet(context, place);
    if (!mounted) {
      return;
    }
    switch (action) {
      case SavedPlaceSheetAction.change:
        await _pickInto(place.slot);
      case SavedPlaceSheetAction.remove:
        await _remove(place);
      case null:
        break;
    }
  }

  Future<void> _remove(SavedPlace place) async {
    final l = AppLocalizations.of(context);
    final repo = ref.read(savedPlacesRepositoryProvider);
    try {
      await repo.remove(place.slot);
    } on Object {
      if (mounted) {
        _showSnack(l.homeSaveFailed);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _showSnack(
      l.homeSlotRemoved(l.slotLabel(place.slot)),
      action: SnackBarAction(
        label: l.commonUndo,
        onPressed: () => unawaited(_restore(place)),
      ),
    );
  }

  Future<void> _restore(SavedPlace place) async {
    final failed = AppLocalizations.of(context).homeSaveFailed;
    try {
      await ref.read(savedPlacesRepositoryProvider).restore(place);
    } on Object {
      if (mounted) {
        _showSnack(failed);
      }
    }
  }

  void _onRecentTap(TripRecord record) =>
      _openDraft(TripDraft.fromRecord(record));

  Future<void> _openOnboarding() async {
    await context.openOnboarding();
    if (mounted) {
      _refreshReadiness();
    }
  }

  Future<void> _openBatteryGuide() async {
    await context.openBatteryGuide();
    if (mounted) {
      _refreshReadiness();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final greeting = greetingFor(ref.watch(clockProvider)());
    final activeTrip = ref.watch(activeTripProvider).value;
    final savedPlaces = ref.watch(savedPlacesProvider);
    final recentTrips = ref.watch(recentTripsProvider);
    final readiness = ref.watch(readinessProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            NapSpace.page,
            NapSpace.s24,
            NapSpace.page,
            NapSpace.s16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HomeHeader(greeting: l.greeting(greeting), title: l.homeTitle),
              if (activeTrip != null) ...[
                const SizedBox(height: NapSpace.section),
                ActiveTripCard(
                  destinationName: activeTrip.destinationName,
                  onOpen: _openTracking,
                ),
              ],
              const SizedBox(height: NapSpace.section),
              NapSearchField(
                hint: l.homeSearchHint,
                readOnly: true,
                onTap: () => unawaited(context.openDestinationSearch()),
              ),
              const SizedBox(height: NapSpace.section),
              NapSectionHeader(l.homeSavedSection),
              const SizedBox(height: NapSpace.s10),
              SavedPlacesGrid(
                places: savedPlaces.value ?? const {},
                locked: savedPlaces.hasError,
                // Never offer "Thêm" before the saved places are known.
                loading: savedPlaces.isLoading && !savedPlaces.hasValue,
                onTap: _onSlotTap,
                onLongPress: (place) => unawaited(_onSlotLongPress(place)),
              ),
              const SizedBox(height: NapSpace.section),
              NapSectionHeader(l.homeRecentSection),
              const SizedBox(height: NapSpace.s10),
              if (recentTrips.hasValue || recentTrips.hasError)
                RecentTripsSection(
                  trips: recentTrips.hasError ? null : recentTrips.value,
                  onTap: _onRecentTap,
                ),
              const SizedBox(height: NapSpace.section),
              ReadinessCard(
                readiness: readiness,
                onRetry: _refreshReadiness,
                onOpenPermissions: () => unawaited(_openOnboarding()),
                onOpenBatteryGuide: () => unawaited(_openBatteryGuide()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const new({required this.greeting, required this.title});

  final String greeting;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: NapSpace.s4,
      children: [
        Text(
          greeting,
          style: context
              .napStyle(NapTypography.body14)
              .copyWith(color: context.napColors.textSecondary),
        ),
        Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.napText.headlineMedium,
          ),
        ),
      ],
    );
  }
}

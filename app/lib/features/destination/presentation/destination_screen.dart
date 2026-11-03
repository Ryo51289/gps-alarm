import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/places/places_models.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/destination_strings.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_bottom_bar.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';
import 'package:napstop/features/destination/presentation/widgets/map_unavailable_placeholder.dart';
import 'package:napstop/features/destination/presentation/widgets/offline_section.dart';
import 'package:napstop/features/destination/presentation/widgets/places_section.dart';
import 'package:napstop/features/destination/presentation/widgets/save_place_sheet.dart';
import 'package:napstop/features/home/presentation/home_providers.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Panel sizes, fractions of the area between the search bar and the bottom
/// bar (T23 §9).
const double _kSheetMin = 0.30;
const double _kSheetInitial = 0.55;
const double _kSheetMax = 0.92;

/// Height of the floating top bar under the status bar (8 + 48 + 8).
const double _kTopBarHeight = NapSpace.s8 + NapSizes.minTouch + NapSpace.s8;

/// Map kept visible under the top bar whatever the panel size.
const double _kMinVisibleMap = NapSizes.minTouch;

/// Screen 2 "Chọn điểm đến" (T23 §9, §10). With [pickMode] (`?mode=pick`)
/// confirming pops the `TripDestination` instead of opening screen 3.
class DestinationScreen extends ConsumerStatefulWidget {
  const new({this.pickMode = false, super.key});

  final bool pickMode;

  @override
  ConsumerState<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends ConsumerState<DestinationScreen> {
  /// This screen's own controller (review T23 #12).
  final Object _screenKey = Object();
  late final NotifierProvider<DestinationController, DestinationState>
  _provider = destinationControllerFamily(_screenKey);
  final _query = TextEditingController();

  /// "Chọn …" is navigating: a second tap is ignored (review T23 #14).
  bool _navigating = false;
  final _focus = FocusNode();
  final _sheet = DraggableScrollableController();
  Timer? _paddingTimer;
  double _extent = _kSheetInitial;
  double _areaHeight = 0;
  double _mapBottom = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    // A failed read of the Maps configuration is retried on every visit.
    if (ref.read(mapsConfigProvider).hasError) {
      ref.invalidate(mapsConfigProvider);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePadding());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ref
        .read(_provider.notifier)
        .setLanguage(Localizations.localeOf(context).languageCode);
  }

  @override
  void dispose() {
    _paddingTimer?.cancel();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _query.dispose();
    _sheet.dispose();
    super.dispose();
  }

  DestinationController get _controller => ref.read(_provider.notifier);

  void _onFocus() {
    if (_focus.hasFocus) {
      _moveSheet(_kSheetMax);
    }
  }

  void _moveSheet(double size) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheet.isAttached) {
        return;
      }
      final duration = NapMotion.of(context, NapMotion.standard);
      if (duration == Duration.zero) {
        _sheet.jumpTo(size);
      } else {
        _sheet.animateTo(size, duration: duration, curve: NapMotion.curve);
      }
    });
  }

  /// Shows the map after a choice: keyboard down, panel at its smallest.
  void _collapse() {
    _focus.unfocus();
    _moveSheet(_kSheetMin);
  }

  bool _onSheetNotification(DraggableScrollableNotification n) {
    _paddingTimer?.cancel();
    _paddingTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) {
        return;
      }
      setState(() => _extent = n.extent);
      _updatePadding();
    });
    return false;
  }

  /// Map padding = what the panel and the bottom bar cover, so the Google
  /// logo stays visible (Places/Maps attribution terms).
  void _updatePadding() {
    if (!mounted) {
      return;
    }
    final size = MediaQuery.sizeOf(context);
    final top = MediaQuery.paddingOf(context).top + _kTopBarHeight;
    final sheetTop = top + _areaHeight * (1 - _extent);
    final padding = math.max(
      0,
      math.min(size.height - sheetTop, size.height - top - _kMinVisibleMap),
    );
    if ((padding - _mapBottom).abs() >= 1) {
      setState(() => _mapBottom = padding.toDouble());
    }
  }

  void _showSnack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), action: action, persist: false),
      );
  }

  void _onQuery(String value) => _controller.setQuery(value);

  void _clearQuery() {
    _query.clear();
    _controller.setQuery('');
  }

  void _onSelectStation(Station s) {
    _controller.selectStation(s);
    _collapse();
  }

  Future<void> _onSelectPrediction(PlacePrediction p) async {
    final failed = AppLocalizations.of(context).destinationPlaceResolveFailed;
    final ok = await _controller.selectPrediction(p);
    if (!mounted || ok == null) {
      return;
    }
    if (ok) {
      _collapse();
    } else {
      _showSnack(failed);
    }
  }

  void _onLongPress(MapPoint p) {
    _controller.dropPin(
      p,
      pinnedName: AppLocalizations.of(context).destinationPinned,
    );
  }

  void _onPinDragEnd(MapPoint p) {
    final l = AppLocalizations.of(context);
    final moved = _controller.movePin(
      p,
      pinnedName: l.destinationPinned,
      pinnedDetail: l.pinnedFrom,
    );
    if (moved == null) {
      return;
    }
    _showSnack(
      l.destinationPinMoved(formatDistanceShort(moved.round(), l.localeName)),
      action: SnackBarAction(
        label: l.commonUndo,
        onPressed: () {
          if (mounted) {
            _controller.undoPin();
          }
        },
      ),
    );
  }

  void _confirm() {
    final selection = ref.read(_provider).selection;
    if (selection == null || _navigating) {
      return;
    }
    final destination = selection.destination;
    if (!destination.isValid) {
      _showSnack(AppLocalizations.of(context).homeSaveFailed);
      return;
    }
    // Leaving screen 2 (picker pop or screen 3 on top): nothing typed may
    // still reach Google afterwards (test report T23 B1).
    _controller.cancelPending();
    _navigating = true;
    if (widget.pickMode) {
      // No destination_selected here: screen 1 logs it when the saved place
      // is used (T23 §3).
      context.pop(destination);
      return;
    }
    // T29: destination_selected {source, kind} is logged here.
    unawaited(_openAlarmSettings(destination, selection.source));
  }

  /// Screen 3 on top; screen 2 stays below it. Back from screen 3 resumes
  /// what [DestinationController.cancelPending] stopped.
  Future<void> _openAlarmSettings(
    TripDestination destination,
    DestinationSource source,
  ) async {
    await context.openAlarmSettings(
      TripDraft(destination: destination, source: source),
    );
    if (mounted) {
      _navigating = false;
      _controller.resume();
    }
  }

  Future<void> _save() async {
    final selection = ref.read(_provider).selection;
    if (selection == null) {
      return;
    }
    final l = AppLocalizations.of(context);
    final current = ref.read(savedPlacesProvider).value ?? const {};
    final slot = await showSavePlaceSheet(context, current);
    if (slot == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(savedPlacesRepositoryProvider)
          .upsert(slot, selection.destination);
    } on Object {
      if (mounted) {
        _showSnack(l.homeSaveFailed);
      }
      return;
    }
    if (mounted) {
      _showSnack(l.destinationSaved(l.savedSlotLabel(slot)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(_provider);
    final config = ref.watch(mapsConfigProvider);
    if (!widget.pickMode) {
      // Keeps the slots fresh for the save sheet.
      ref.watch(savedPlacesProvider);
    }
    final mapAvailable = config.value?.apiKey != null;
    final selection = state.selection;
    final topInset = MediaQuery.paddingOf(context).top;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final Widget map;
    if (mapAvailable) {
      map = ref.watch(destinationMapBuilderProvider)(
        DestinationMapProps(
          point: selection?.point,
          radiusM: kPreviewRadiusM,
          cameraRequestId: state.cameraRequestId,
          bottomPadding: _mapBottom,
          onLongPress: _onLongPress,
          onPinDragEnd: _onPinDragEnd,
        ),
      );
    } else {
      map = MapUnavailablePlaceholder(
        message: config.isLoading ? null : l.destinationMapUnavailable,
        bottomPadding: _mapBottom,
      );
    }

    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(key: const ValueKey('map'), child: map),
          // Keys: the badge comes and goes, the panel (and its sheet
          // controller) must keep its element.
          if (selection != null && mapAvailable)
            Positioned(
              key: const ValueKey('zone-badge'),
              top: topInset + _kTopBarHeight,
              right: NapSpace.s16,
              child: NapBadge(
                label: l.destinationAlarmZoneBadge(
                  formatDistanceShort(kPreviewRadiusM.round(), l.localeName),
                ),
                tone: NapTone.accent,
                size: NapBadgeSize.medium,
              ),
            ),
          Positioned.fill(
            key: const ValueKey('panel'),
            top: topInset + _kTopBarHeight,
            bottom: keyboard,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, area) {
                      _areaHeight = area.maxHeight;
                      return NotificationListener<
                        DraggableScrollableNotification
                      >(
                        onNotification: _onSheetNotification,
                        child: DraggableScrollableSheet(
                          controller: _sheet,
                          snap: true,
                          snapSizes: const [
                            _kSheetMin,
                            _kSheetInitial,
                            _kSheetMax,
                          ],
                          initialChildSize: _kSheetInitial,
                          minChildSize: _kSheetMin,
                          maxChildSize: _kSheetMax,
                          builder: (context, scroll) => _SheetBody(
                            scroll: scroll,
                            state: state,
                            showPinHint:
                                mapAvailable && _extent <= _kSheetMin + 0.01,
                            onFilter: _controller.setFilter,
                            isSelected: _controller.isSelectedStation,
                            onSelectStation: _onSelectStation,
                            onSelectPrediction: (p) =>
                                unawaited(_onSelectPrediction(p)),
                            onRetry: () =>
                                ref.invalidate(stationCatalogProvider),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                DestinationBottomBar(
                  confirmLabel: selection == null
                      ? l.destinationConfirmDisabled
                      : l.destinationConfirm(selection.destination.name),
                  saveLabel: l.destinationSave,
                  showSave: !widget.pickMode,
                  onConfirm: selection == null ? null : _confirm,
                  onSave: selection == null ? null : () => unawaited(_save()),
                ),
              ],
            ),
          ),
          Positioned(
            key: const ValueKey('top-bar'),
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  NapSpace.s16,
                  NapSpace.s8,
                  NapSpace.s16,
                  NapSpace.s8,
                ),
                child: Row(
                  spacing: NapSpace.s10,
                  children: [
                    NapIconButton(
                      icon: NapIcons.back,
                      semanticLabel: l.commonBack,
                      variant: NapIconButtonVariant.floating,
                      size: NapSizes.minTouch,
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: NapSearchField(
                        hint: l.destinationSearchHint,
                        controller: _query,
                        focusNode: _focus,
                        autofocus: true,
                        variant: NapSearchFieldVariant.floating,
                        onChanged: _onQuery,
                        trailing: state.query.isEmpty
                            ? null
                            : NapIconButton(
                                icon: NapIcons.clear,
                                semanticLabel: l.destinationClearQuery,
                                variant: NapIconButtonVariant.plain,
                                onPressed: _clearQuery,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    // Back (app button or system) stops pending Places/distance work at
    // once: the screen stays mounted for the exit animation (test report
    // T23 B1).
    return PopScope<Object?>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _controller.cancelPending();
        }
      },
      child: scaffold,
    );
  }
}

/// Scrollable content of the panel: chips, pin hint, results.
class _SheetBody extends StatelessWidget {
  const new({
    required this.scroll,
    required this.state,
    required this.showPinHint,
    required this.onFilter,
    required this.isSelected,
    required this.onSelectStation,
    required this.onSelectPrediction,
    required this.onRetry,
  });

  final ScrollController scroll;
  final DestinationState state;
  final bool showPinHint;
  final ValueChanged<DestinationFilter> onFilter;
  final bool Function(Station s) isSelected;
  final ValueChanged<Station> onSelectStation;
  final ValueChanged<PlacePrediction> onSelectPrediction;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        controller: scroll,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: NapSheetContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: NapSpace.s16),
                  child: Row(
                    spacing: NapSpace.s8,
                    children: [
                      for (final f in DestinationFilter.values)
                        NapChip(
                          label: l.filterLabel(f),
                          selected: state.filter == f,
                          style: NapChipStyle.filter,
                          compact: true,
                          onTap: () => onFilter(f),
                        ),
                    ],
                  ),
                ),
                if (showPinHint)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      NapSpace.s16,
                      NapSpace.s8,
                      NapSpace.s16,
                      0,
                    ),
                    child: Text(
                      l.destinationPinHint,
                      style: context
                          .napStyle(NapTypography.caption)
                          .copyWith(color: c.textSecondary),
                    ),
                  ),
                const SizedBox(height: NapSpace.s8),
                if (state.filter == DestinationFilter.places)
                  PlacesSection(
                    places: state.places,
                    onSelect: onSelectPrediction,
                  )
                else
                  OfflineSection(
                    state: state,
                    isSelected: isSelected,
                    onSelect: onSelectStation,
                    onRetry: onRetry,
                    onOpenPlaces: () => onFilter(DestinationFilter.places),
                  ),
                const SizedBox(height: NapSpace.s16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

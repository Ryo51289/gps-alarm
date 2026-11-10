import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/destination_strings.dart';
import 'package:napstop/features/destination/presentation/widgets/address_section.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_bottom_bar.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';
import 'package:napstop/features/destination/presentation/widgets/map_unavailable_placeholder.dart';
import 'package:napstop/features/destination/presentation/widgets/offline_section.dart';
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

/// Room left for the zone badge under the top bar when framing a choice
/// (medium `NapBadge`: 6 + line + 6).
const double _kBadgeHeight = 32;

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

  /// D9: map height (top of the screen to the top of the resting panel);
  /// null until the panel area was measured (the map then fills the
  /// screen for that first frame).
  double? _mapHeight;

  /// Part of the map the panel covers now.
  double _mapCovered = 0;
  MapPadding _framePadding = kNoMapPadding;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePadding());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // T27 D11: a `go` (screen 4 or 8) or a `replace` removes this route,
    // which stays mounted for the transition (longer than the distance
    // debounce): stop at once. Covered by a sheet or screen 3, the route
    // is still active and nothing changes here.
    final route = ModalRoute.of(context);
    if (route != null && !route.isActive) {
      _controller.cancelPending();
    }
  }

  /// Screen 2 leaves the tree however it goes (a `go` to screen 4 or 8,
  /// a `replace`): no distance call may still run afterwards (T27
  /// D11, review T23 round 3 #10). Idempotent.
  @override
  void deactivate() {
    _controller.cancelPending();
    super.deactivate();
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
  /// The frame padding is computed for the panel's destination at once, so
  /// the camera request of the same choice frames the area left visible
  /// once the panel has settled.
  void _collapse() {
    _focus.unfocus();
    _moveSheet(_kSheetMin);
    _extent = _kSheetMin;
    _updatePadding();
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

  /// The panel area changed size (first layout, rotation, keyboard):
  /// measure again after this frame.
  void _onAreaHeight(double height) {
    if (height == _areaHeight) {
      return;
    }
    _areaHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePadding());
  }

  /// T23.3 D9: the map ends at the top of the panel at its lowest resting
  /// size, so the Apple logo and Legal link are never covered by the
  /// resting panel. The keyboard is added back to the measured area: the
  /// map keeps its size while the keyboard moves. The frame padding
  /// follows the panel's current size.
  void _updatePadding() {
    if (!mounted || _areaHeight <= 0) {
      return;
    }
    final topInset = MediaQuery.paddingOf(context).top;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final mapHeight = destinationMapHeight(
      topInset: topInset,
      topBarHeight: _kTopBarHeight,
      sheetAreaHeight: _areaHeight + keyboard,
      sheetMin: _kSheetMin,
    );
    final sheetTop = topInset + _kTopBarHeight + _areaHeight * (1 - _extent);
    final covered = math.max(0, mapHeight - sheetTop).toDouble();
    final padding = destinationFramePadding(
      topInset: topInset,
      topBarHeight: _kTopBarHeight,
      badgeHeight: _kBadgeHeight,
      mapHeight: mapHeight,
      sheetTopY: sheetTop,
    );
    final old = _mapHeight;
    if (old == null ||
        (mapHeight - old).abs() >= 1 ||
        (covered - _mapCovered).abs() >= 1 ||
        padding != _framePadding) {
      setState(() {
        _mapHeight = mapHeight;
        _mapCovered = covered;
        _framePadding = padding;
      });
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

  Future<void> _onSelectAddress(int nativeIndex) async {
    final pick = await _controller.selectAddress(nativeIndex);
    if (!mounted) {
      return;
    }
    final l = AppLocalizations.of(context);
    switch (pick) {
      case AddressPick.picked:
        _collapse();
      case AddressPick.outsideArea:
        _showSnack(l.destinationAddressOutsideArea);
      case AddressPick.offline:
        _showSnack(l.destinationAddressOffline);
      case AddressPick.failed:
        _showSnack(l.destinationAddressResolveFailed);
      case AddressPick.ignored:
        break;
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
    // Leaving screen 2 (picker pop or screen 3 on top): no distance call may
    // still run afterwards (test report T23 B1).
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
    if (!widget.pickMode) {
      // Keeps the slots fresh for the save sheet.
      ref.watch(savedPlacesProvider);
    }
    // T23.2 D4: no builder (no map on this platform yet) = placeholder.
    final mapBuilder = ref.watch(destinationMapBuilderProvider);
    final mapAvailable = mapBuilder != null;
    final addressOn = ref.watch(addressSearchEnabledProvider);
    final selection = state.selection;
    final topInset = MediaQuery.paddingOf(context).top;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final Widget map;
    if (mapBuilder != null) {
      map = mapBuilder(
        DestinationMapProps(
          point: selection?.point,
          radiusM: kPreviewRadiusM,
          cameraRequestId: state.cameraRequestId,
          framePadding: _framePadding,
          onLongPress: _onLongPress,
          onPinDragEnd: _onPinDragEnd,
        ),
      );
    } else {
      map = MapUnavailablePlaceholder(
        message: l.destinationMapUnavailable,
        bottomPadding: _mapCovered,
      );
    }

    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // D9: from the top of the screen to the top of the resting panel
          // (map and placeholder alike).
          Positioned(
            key: const ValueKey('map'),
            top: 0,
            left: 0,
            right: 0,
            height: _mapHeight ?? MediaQuery.sizeOf(context).height,
            child: map,
          ),
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
                      _onAreaHeight(area.maxHeight);
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
                            showNoMatchPinHint: mapAvailable,
                            onFilter: _controller.setFilter,
                            isSelected: _controller.isSelectedStation,
                            onSelectStation: _onSelectStation,
                            isSelectedAddress: _controller.isSelectedAddress,
                            onSelectAddress: _onSelectAddress,
                            addressOn: addressOn,
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
                        hint: addressOn
                            ? l.destinationSearchHintWithAddress
                            : l.destinationSearchHint,
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
    // Back (app button or system) stops pending distance work at
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
    required this.showNoMatchPinHint,
    required this.onFilter,
    required this.isSelected,
    required this.onSelectStation,
    required this.isSelectedAddress,
    required this.onSelectAddress,
    required this.addressOn,
    required this.onRetry,
  });

  final ScrollController scroll;
  final DestinationState state;
  final bool showPinHint;
  final bool showNoMatchPinHint;
  final ValueChanged<DestinationFilter> onFilter;
  final bool Function(Station s) isSelected;
  final ValueChanged<Station> onSelectStation;
  final bool Function(AddressSuggestion s) isSelectedAddress;
  final ValueChanged<int> onSelectAddress;
  final bool addressOn;
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
                OfflineSection(
                  state: state,
                  isSelected: isSelected,
                  onSelect: onSelectStation,
                  onRetry: onRetry,
                  showNoMatchPinHint: showNoMatchPinHint,
                  addressOn: addressOn,
                ),
                AddressSection(
                  state: state,
                  isSelected: isSelectedAddress,
                  onSelect: onSelectAddress,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/features/onboarding/presentation/onboarding_controller.dart';
import 'package:napstop/features/onboarding/presentation/widgets/battery_card.dart';
import 'package:napstop/features/onboarding/presentation/widgets/permission_explainer_sheet.dart';
import 'package:napstop/features/onboarding/presentation/widgets/permission_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 0 "Cấp quyền" (T21 §7). First run: the initial route, no back
/// button, main button "Tiếp tục". Later (from the home card): back button,
/// main button "Xong". Never blocks: screen 3 blocks the trip (D11).
class OnboardingScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from Settings or a system dialog: read the real state again.
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() =>
      unawaited(ref.read(onboardingControllerProvider.notifier).refresh());

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), persist: false));
  }

  Future<void> _onAction(OnboardingItem item, PlatformMsg platform) async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    if (item.explainer != OnboardingExplainer.none) {
      final go = await showPermissionExplainer(context, item.explainer);
      if (!go || !mounted) {
        return;
      }
    }
    final outcome = await controller.act(item);
    if (!mounted) {
      return;
    }
    final l = AppLocalizations.of(context);
    switch (outcome) {
      case OnboardingOutcome.requestFailed:
        _showSnack(l.onboardingRequestFailed);
      case OnboardingOutcome.settingsUnavailable:
        _showSnack(
          platform == PlatformMsg.ios &&
                  item.settings == SettingsTargetMsg.locationServices
              ? l.onboardingLocationServicesIos
              : l.onboardingSettingsUnavailable,
        );
      case OnboardingOutcome.done || OnboardingOutcome.ignored:
        break;
    }
  }

  Future<void> _openGuide() async {
    await context.openBatteryGuide();
    if (mounted) {
      _refresh();
    }
  }

  Future<void> _finish() async {
    await markOnboardingCompleted(ref.read(onboardingStoreProvider));
    // T29: permission_snapshot is logged here (no telemetry before T29).
    if (!mounted) {
      return;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    final firstRun = !GoRouter.of(context).canPop();
    final async = ref.watch(onboardingControllerProvider);
    final battery = ref.watch(onboardingBatteryCardProvider);
    final state = async.hasError ? null : async.value;
    final busy = state?.busy ?? false;
    final hideIllustration = MediaQuery.textScalerOf(context).scale(16) > 24;

    final content = <Widget>[
      if (!hideIllustration) const _Illustration(),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NapSpace.s8,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.onboardingTitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: text.headlineMedium,
            ),
          ),
          Text(
            l.onboardingSubtitle,
            style: text.bodyMedium!.copyWith(color: c.textSecondary),
          ),
        ],
      ),
      if (async.hasError)
        NapBanner(
          message: l.onboardingError,
          action: NapButton(
            label: l.commonRetry,
            onPressed: _refresh,
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.small,
          ),
        )
      else if (state == null)
        const _Skeleton()
      else ...[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: NapSpace.s12,
          children: [
            for (final item in state.items)
              PermissionRow(
                key: ValueKey('onboarding-${item.kind.name}'),
                item: item,
                onAction: busy
                    ? null
                    : () => unawaited(_onAction(item, state.device.platform)),
              ),
          ],
        ),
        if (battery != null)
          BatteryCard(
            model: battery,
            onOpenGuide: busy ? null : () => unawaited(_openGuide()),
          ),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!firstRun)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: NapSpace.page),
                child: NapScreenHeader(
                  title: l.appScreenOnboardingTitle,
                  onBack: () => context.pop(),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NapSpace.page,
                  NapSpace.s24,
                  NapSpace.page,
                  NapSpace.s16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: NapSpace.s24,
                  children: content,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NapSpace.page,
                0,
                NapSpace.page,
                NapSpace.s28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: NapSpace.s8,
                children: [
                  NapButton(
                    label: firstRun ? l.onboardingContinue : l.commonDone,
                    onPressed: () => unawaited(_finish()),
                  ),
                  if (state != null && !state.check.canStart)
                    Text(
                      l.onboardingMissingNote,
                      textAlign: TextAlign.center,
                      style: text.bodySmall!.copyWith(color: c.danger),
                    ),
                  Text(
                    l.onboardingPrivacyNote,
                    textAlign: TextAlign.center,
                    style: context
                        .napStyle(NapTypography.caption)
                        .copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Decorative card with two icons; hidden at large text scales.
class _Illustration extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return ExcludeSemantics(
      child: NapCard(
        variant: NapCardVariant.filled,
        radius: NapRadii.r20,
        child: SizedBox(
          height: 128,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: NapSpace.s24,
            children: [
              Icon(NapIcons.coach, size: 48, color: c.accent),
              Icon(NapIcons.sleep, size: 48, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading rows: two blank cards, no text.
class _Skeleton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return ExcludeSemantics(
      child: Column(
        spacing: NapSpace.s12,
        children: [
          for (var i = 0; i < 2; i++)
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: BorderRadius.circular(NapRadii.r14),
              ),
            ),
        ],
      ),
    );
  }
}

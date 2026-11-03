import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Largest share of the screen height taken by the error banner and the
/// summary line of [StartBar]; more scrolls inside the bar.
const double kStartBarInfoMaxFraction = 0.4;

/// Action of the error banner: a label and what it does.
typedef StartBarAction = ({String label, VoidCallback onPressed});

/// Bottom bar of screen 3: error banner, summary line and the start button
/// (T25 §3). Fixed at the bottom; grows with the text scale.
class StartBar extends StatefulWidget {
  const new({
    required this.summaryValue,
    required this.starting,
    required this.onStart,
    this.error,
    this.errorAction,
    super.key,
  });

  /// Bold part of "Sẽ báo khi …".
  final String summaryValue;
  final bool starting;

  /// Null disables the button (still loading).
  final VoidCallback? onStart;
  final String? error;
  final StartBarAction? errorAction;

  @override
  State<StartBar> createState() => _StartBarState();
}

class _StartBarState extends State<StartBar> {
  /// Shared by the info area and its scrollbar.
  final ScrollController _infoScroll = ScrollController();

  @override
  void dispose() {
    _infoScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final error = widget.error;
    final action = widget.errorAction;
    final starting = widget.starting;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NapSpace.page,
          NapSpace.s12,
          NapSpace.page,
          NapSpace.s12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: NapSpace.s10,
          children: [
            // Error banner + summary: capped and scrollable, so at a large
            // text scale the bar never pushes the content (or the start
            // button) off a small screen (T25.1, test report T25 #1).
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    kStartBarInfoMaxFraction,
              ),
              // The thumb stays visible while the area can scroll (a hint
              // that "Thử lại" may sit below the edge); none otherwise.
              child: Scrollbar(
                controller: _infoScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _infoScroll,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: NapSpace.s10,
                    children: [
                      if (error != null)
                        NapBanner(
                          tone: NapTone.danger,
                          announce: true,
                          message: error,
                          action: action == null
                              ? null
                              : NapButton(
                                  label: action.label,
                                  onPressed: action.onPressed,
                                  variant: NapButtonVariant.secondary,
                                  size: NapButtonSize.small,
                                ),
                        ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${l.alarmSettingsSummaryPrefix} '),
                            TextSpan(
                              text: widget.summaryValue,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: context
                            .napStyle(NapTypography.body14)
                            .copyWith(color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            NapButton(
              label: starting ? l.alarmSettingsStarting : l.alarmSettingsStart,
              icon: NapIcons.play,
              onPressed: starting ? null : widget.onStart,
            ),
          ],
        ),
      ),
    );
  }
}

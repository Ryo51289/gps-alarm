import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Shown instead of the map when this platform has no map yet
/// (`destinationMapBuilderProvider` null, T23.2 D4).
class MapUnavailablePlaceholder extends StatelessWidget {
  const new({required this.message, this.bottomPadding = 0, super.key});

  final String message;

  /// Height of the panel over the bottom: the message stays above it.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return ColoredBox(
      color: c.fill,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            NapSpace.page,
            NapSizes.minTouch + NapSpace.s16,
            NapSpace.page,
            bottomPadding,
          ),
          // Clipped, not overflowing, when the panel covers most of it.
          child: Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: NapSpace.s8,
                children: [
                  Icon(
                    NapIcons.place,
                    size: NapSizes.iconXLarge,
                    color: c.textSecondary,
                  ),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.napText.bodySmall!.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

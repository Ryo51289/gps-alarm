import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:url_launcher/url_launcher.dart';

/// Copyright page of the OpenStreetMap data (ODbL attribution, T24 §8).
final Uri kOsmCopyrightUri = Uri.parse(
  'https://www.openstreetmap.org/copyright',
);

/// Opens a URL outside the app; false when nothing could open it. Widget
/// tests override it to record the call.
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// "Dữ liệu ga/bến © OpenStreetMap contributors" under the offline results;
/// a link to [kOsmCopyrightUri].
class OsmAttribution extends ConsumerWidget {
  const new({required this.label, required this.hint, super.key});

  final String label;

  /// Screen reader hint ("Mở trang bản quyền OpenStreetMap").
  final String hint;

  Future<void> _open(ExternalUrlLauncher launch) async {
    try {
      // false (no browser): nothing else to offer, the text stays visible.
      await launch(kOsmCopyrightUri);
    } on Object {
      // Same: the attribution is shown, opening the page is a bonus.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.napColors;
    final launch = ref.watch(externalUrlLauncherProvider);
    return Semantics(
      link: true,
      hint: hint,
      child: InkWell(
        onTap: () => unawaited(_open(launch)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: NapSizes.minTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: NapSpace.s16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                label,
                style: context
                    .napStyle(NapTypography.caption)
                    .copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

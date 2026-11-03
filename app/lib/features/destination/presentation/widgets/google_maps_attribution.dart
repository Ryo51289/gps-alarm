import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Attribution under Places results shown without a Google map. Never
/// translated or re-cased (Places policies), so not an ARB string, like
/// `kAppName`.
const String kGoogleMapsAttribution = 'Google Maps';

/// Policy color of the text on a light background.
const Color _kOnLight = Color(0xFF5E5E5E);

/// "Google Maps" line under the Places results (T23 §9): Roboto 12 (system
/// font on iOS, RK8), #5E5E5E on light, white on dark, one line.
class GoogleMapsAttribution extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NapSpace.s16,
        NapSpace.s10,
        NapSpace.s16,
        NapSpace.s8,
      ),
      child: Semantics(
        label: kGoogleMapsAttribution,
        child: ExcludeSemantics(
          child: Text(
            kGoogleMapsAttribution,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 12,
              height: 1.4,
              color: dark ? Colors.white : _kOnLight,
            ),
          ),
        ),
      ),
    );
  }
}

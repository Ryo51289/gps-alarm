import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shadow tokens (spec T20 sections 1.2, 3.1).
///
/// Dark surfaces get no shadow: floating elements draw a 1 px `border`
/// instead ([borderInsteadOfShadow]).
@immutable
final class NapShadows extends ThemeExtension<NapShadows> {
  const new({
    required this.floating,
    required this.thumb,
    required this.sheet,
    required this.borderInsteadOfShadow,
  });

  /// Buttons and labels floating on the map.
  final List<BoxShadow> floating;

  /// Selected segment of a segmented control.
  final List<BoxShadow> thumb;

  /// Non-modal sheet panel resting on the map.
  final List<BoxShadow> sheet;

  /// True on dark themes: floating elements use a 1 px border.
  final bool borderInsteadOfShadow;

  static const NapShadows light = NapShadows(
    floating: [
      BoxShadow(color: Color(0x1F000000), offset: Offset(0, 2), blurRadius: 8),
    ],
    thumb: [
      BoxShadow(color: Color(0x1F000000), offset: Offset(0, 1), blurRadius: 3),
    ],
    sheet: [
      BoxShadow(
        color: Color(0x14000000),
        offset: Offset(0, -4),
        blurRadius: 16,
      ),
    ],
    borderInsteadOfShadow: false,
  );

  /// Used by the dark and alarm themes.
  static const NapShadows dark = NapShadows(
    floating: [],
    thumb: [],
    sheet: [],
    borderInsteadOfShadow: true,
  );

  @override
  NapShadows copyWith({
    List<BoxShadow>? floating,
    List<BoxShadow>? thumb,
    List<BoxShadow>? sheet,
    bool? borderInsteadOfShadow,
  }) {
    return NapShadows(
      floating: floating ?? this.floating,
      thumb: thumb ?? this.thumb,
      sheet: sheet ?? this.sheet,
      borderInsteadOfShadow:
          borderInsteadOfShadow ?? this.borderInsteadOfShadow,
    );
  }

  @override
  NapShadows lerp(covariant NapShadows? other, double t) {
    if (other == null || t == 0) {
      return this;
    }
    if (t == 1) {
      return other;
    }
    return NapShadows(
      floating: BoxShadow.lerpList(floating, other.floating, t)!,
      thumb: BoxShadow.lerpList(thumb, other.thumb, t)!,
      sheet: BoxShadow.lerpList(sheet, other.sheet, t)!,
      borderInsteadOfShadow: t < 0.5
          ? borderInsteadOfShadow
          : other.borderInsteadOfShadow,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NapShadows &&
          listEquals(floating, other.floating) &&
          listEquals(thumb, other.thumb) &&
          listEquals(sheet, other.sheet) &&
          borderInsteadOfShadow == other.borderInsteadOfShadow;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(floating),
    Object.hashAll(thumb),
    Object.hashAll(sheet),
    borderInsteadOfShadow,
  );
}

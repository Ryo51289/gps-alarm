/// Display name and aliases of a station (spec T24 §4.3).
library;

import 'package:stationgen/src/classify.dart';
import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/prefixes.dart';

/// Maximum number of aliases per station.
const int kMaxAliases = 5;

/// Display name and aliases.
final class StationNames {
  const new(this.name, this.aliases);

  final String name;
  final List<String> aliases;
}

final RegExp _spaces = RegExp(r'\s+');

/// Trims and collapses runs of white space.
String collapseSpaces(String s) => s.trim().replaceAll(_spaces, ' ');

/// True when [s] contains combining marks (U+0300–U+036F, NFD text).
bool hasCombiningMarks(String s) =>
    s.runes.any((r) => r >= 0x300 && r <= 0x36F);

/// Display name for [rawName]: collapsed spaces; trains get a `Ga ` prefix
/// unless the folded name already starts with `ga` or `nha ga`.
String displayName(String rawName, StationKind kind) {
  final name = collapseSpaces(rawName);
  if (kind != StationKind.train) {
    return name;
  }
  final t = foldTokens(name);
  if (startsWithTokens(t, const ['ga']) ||
      startsWithTokens(t, const ['nha', 'ga'])) {
    return name;
  }
  return 'Ga $name';
}

/// Appends [values] to [aliases] (in order), skipping values that fold to
/// nothing and values whose fold equals the fold of [name] or of an earlier
/// alias; at most [kMaxAliases]. Returns a new list.
List<String> mergeAliasValues(
  String name,
  List<String> aliases,
  Iterable<String> values,
) {
  final out = [...aliases];
  final seen = {foldVi(name), ...aliases.map(foldVi)};
  for (final raw in values) {
    if (out.length >= kMaxAliases) {
      break;
    }
    final v = collapseSpaces(raw);
    final folded = foldVi(v);
    if (folded.isEmpty) {
      continue;
    }
    if (seen.add(folded)) {
      out.add(v);
    }
  }
  return out;
}

/// Name and aliases for an element with [tags] that classified as [kind].
/// Requires a non-empty [rawNameOf].
StationNames namesOf(Map<String, String> tags, StationKind kind) {
  final rawName = rawNameOf(tags)!;
  final name = displayName(rawName, kind);
  final values = <String>[
    ...?tags['alt_name']?.split(';'),
    ...?tags['old_name']?.split(';'),
    ?tags['official_name'],
    ?tags['short_name'],
  ];
  final osmName = tags['name']?.trim();
  if (tags['name:vi'] != null &&
      osmName != null &&
      osmName.isNotEmpty &&
      osmName != rawName) {
    values.add(osmName);
  }
  return StationNames(name, mergeAliasValues(name, const [], values));
}

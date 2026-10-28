/// Fixture validation: GPX structure and GPX + expect consistency
/// (spec T02 §7.5).
library;

import 'dart:convert';

import 'package:tracegen/src/fmt.dart';
import 'package:tracegen/src/gpx_writer.dart';
import 'package:tracegen/src/paths.dart';
import 'package:tracegen/src/profile.dart' show kEventNames;
import 'package:xml/xml.dart';

/// Parsed facts of a GPX file needed by the pair checks.
final class GpxSummary {
  const new({required this.segments, required this.firstTime});

  /// Epoch seconds of every `trkpt`, per `trkseg`.
  final List<List<int>> segments;

  /// Text of the first `trkpt` time.
  final String? firstTime;

  int get pointCount => segments.fold(0, (sum, s) => sum + s.length);
}

/// Checks a GPX file; appends `<label>:<location>: <message>` to [errors].
/// Returns null when the document cannot be read at all.
GpxSummary? checkGpx(String label, List<int> bytes, List<String> errors) {
  void err(String where, String message) =>
      errors.add('$label:$where: $message');

  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    err('1', 'byte order mark is not allowed');
  }
  final cr = bytes.indexOf(0x0D);
  if (cr >= 0) {
    final line = bytes.sublist(0, cr).where((b) => b == 0x0A).length + 1;
    err('$line', 'carriage return (CR) is not allowed, use LF');
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException catch (e) {
    err('1', 'not valid UTF-8: ${e.message}');
    return null;
  }
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException catch (e) {
    err('1', 'XML is not well-formed: ${e.message}');
    return null;
  }
  final declaration = doc.declaration;
  if (declaration == null ||
      declaration.getAttribute('encoding')?.toUpperCase() != 'UTF-8') {
    err('1', 'missing XML declaration with encoding="UTF-8"');
  }
  final root = doc.rootElement;
  if (root.name.local != 'gpx' || root.name.namespaceUri != kGpxNamespace) {
    err('/gpx', 'root must be gpx in namespace $kGpxNamespace');
    return null;
  }
  if (root.getAttribute('version') != '1.1') {
    err('/gpx', 'version must be "1.1"');
  }
  if ((root.getAttribute('creator') ?? '').trim().isEmpty) {
    err('/gpx', 'creator must not be empty');
  }
  final tracks = root.findElements('trk', namespaceUri: kGpxNamespace).toList();
  if (tracks.length != 1) {
    err('/gpx', 'expected exactly 1 trk, found ${tracks.length}');
    if (tracks.isEmpty) {
      return null;
    }
  }
  final segs = tracks.first
      .findElements('trkseg', namespaceUri: kGpxNamespace)
      .toList();
  if (segs.isEmpty) {
    err('/gpx/trk', 'expected at least 1 trkseg');
  }
  final segments = <List<int>>[];
  String? firstTime;
  int? previous;
  for (var i = 0; i < segs.length; i++) {
    final points = segs[i]
        .findElements('trkpt', namespaceUri: kGpxNamespace)
        .toList();
    final segPath = '/gpx/trk/trkseg[${i + 1}]';
    if (points.isEmpty) {
      err(segPath, 'expected at least 1 trkpt');
    }
    final times = <int>[];
    for (var k = 0; k < points.length; k++) {
      final pt = points[k];
      final where = '$segPath/trkpt[${k + 1}]';
      final lat = double.tryParse(pt.getAttribute('lat') ?? '');
      if (lat == null || !(lat >= -90 && lat <= 90)) {
        err(where, 'lat must be a number in [-90, 90]');
      }
      final lon = double.tryParse(pt.getAttribute('lon') ?? '');
      if (lon == null || !(lon >= -180 && lon < 180)) {
        err(where, 'lon must be a number in [-180, 180)');
      }
      final timeEl = pt.getElement('time', namespaceUri: kGpxNamespace);
      final timeText = timeEl?.innerText;
      int? t;
      if (timeText != null && isoUtcPattern.hasMatch(timeText)) {
        try {
          t = parseIsoUtc(timeText);
        } on FormatException {
          t = null;
        }
      }
      if (t == null) {
        err(where, 'time must match YYYY-MM-DDTHH:MM:SSZ');
      } else {
        if (previous != null && t <= previous) {
          err(where, 'time must increase strictly');
        }
        previous = t;
        times.add(t);
        firstTime ??= timeText;
      }
      final ext = pt.getElement('extensions', namespaceUri: kGpxNamespace);
      final acc = ext?.getElement('acc', namespaceUri: kNapstopNamespace);
      final accValue = double.tryParse(acc?.innerText ?? '');
      if (accValue == null || !accValue.isFinite || accValue <= 0) {
        err(where, 'napstop:acc is required, finite and > 0');
      }
      final spd = ext?.getElement('spd', namespaceUri: kNapstopNamespace);
      if (spd != null) {
        final v = double.tryParse(spd.innerText);
        if (v == null || !v.isFinite || v < 0) {
          err(where, 'napstop:spd must be finite and >= 0');
        }
      }
    }
    segments.add(times);
  }
  return GpxSummary(segments: segments, firstTime: firstTime);
}

/// Validates the fixture pair `<id>.gpx` + `<id>.expect.json`.
///
/// [gpxLabel] and [expectLabel] prefix every error message; the file names
/// (after the last `/`) are compared with `trace.gpx` and `trace.id`.
List<String> validatePair({
  required String gpxLabel,
  required List<int> gpxBytes,
  required String expectLabel,
  required List<int> expectBytes,
}) {
  final errors = <String>[];
  final gpx = checkGpx(gpxLabel, gpxBytes, errors);

  void err(String where, String message) =>
      errors.add('$expectLabel:$where: $message');

  if (expectBytes.contains(0x0D)) {
    err('1', 'carriage return (CR) is not allowed, use LF');
  }
  Object? json;
  try {
    json = jsonDecode(utf8.decode(expectBytes));
  } on FormatException catch (e) {
    err('1', 'invalid JSON: ${e.message}');
    return errors;
  }
  final root = _J.root(json, err);
  if (root == null) {
    return errors;
  }
  final version = root.integer('schemaVersion');
  if (version != null && version != 1) {
    err('schemaVersion', 'unsupported schema version $version (expected 1)');
    return errors;
  }
  final generator = root.obj('generator');
  generator?.str('name');
  generator?.str('version');

  final trace = root.obj('trace');
  final id = trace?.str('id');
  trace?.str('title');
  final vehicle = trace?.str('vehicle');
  if (vehicle != null && !const ['train', 'coach', 'bus'].contains(vehicle)) {
    err('trace.vehicle', 'must be train, coach or bus');
  }
  final gpxName = trace?.str('gpx');
  trace?.integer('seed');
  trace?.integer('noiseSeed');
  final startTime = trace?.str('startTime');
  final interval = trace?.integer('sampleIntervalS');
  final duration = trace?.integer('durationS');
  final sampleCount = trace?.integer('sampleCount');

  final expectFile = fileNameOf(expectLabel);
  if (id != null && expectFile != '$id.expect.json') {
    err('trace.id', 'does not match file name $expectFile');
  }
  final gpxFile = fileNameOf(gpxLabel);
  if (gpxName != null && gpxName != gpxFile) {
    err('trace.gpx', 'is "$gpxName" but the GPX file is $gpxFile');
  }

  final destination = root.obj('destination');
  destination?.str('id');
  destination?.optStr('name');
  destination?.number('lat');
  destination?.number('lng');

  final truth = root.obj('truth');
  truth?.integer('routeLengthM');
  truth?.integer('destinationRouteM');
  truth?.integer('arrivalT');
  for (final s in truth?.objList('stops') ?? const <_J>[]) {
    s
      ..integer('routeM')
      ..integer('arriveT')
      ..integer('departT')
      ..optStr('name');
  }
  final gaps = <(int, int)>[];
  for (final g in truth?.objList('gpsGaps') ?? const <_J>[]) {
    final from = g.integer('fromT');
    final to = g.integer('toT');
    if (from != null && to != null) {
      if (from >= to) {
        err(g.path, 'fromT must be < toT');
      }
      gaps.add((from, to));
    }
  }
  for (final o in truth?.objList('outliers') ?? const <_J>[]) {
    o
      ..integer('t')
      ..integer('errorM');
    final kind = o.str('kind');
    if (kind != null && kind != 'random' && kind != 'scripted') {
      err('${o.path}.kind', 'must be random or scripted');
    }
  }
  if (truth?.has('overshoot') ?? false) {
    truth?.obj('overshoot')
      ?..integer('closestT')
      ..integer('closestM')
      ..integer('t');
  }

  final milestones = root.obj('milestones');
  for (final m in milestones?.objList('distance') ?? const <_J>[]) {
    m
      ..integer('thresholdM')
      ..integer('routeT');
    if (!m.has('straightT')) {
      err('${m.path}.straightT', 'missing required key');
    } else if (m.raw('straightT') != null) {
      m.integer('straightT');
    }
  }
  for (final m in milestones?.objList('time') ?? const <_J>[]) {
    m
      ..integer('beforeArrivalMin')
      ..integer('t');
  }

  final caseIds = <String>{};
  for (final c in root.objList('cases') ?? const <_J>[]) {
    final caseId = c.str('id');
    if (caseId != null && !caseIds.add(caseId)) {
      err('${c.path}.id', 'duplicate case id "$caseId"');
    }
    final status = c.str('status');
    if (status != null && status != 'draft' && status != 'final') {
      err('${c.path}.status', 'must be draft or final');
    }
    final config = c.obj('config');
    final mode = config?.str('mode');
    if (mode == 'distance') {
      config?.integer('thresholdM');
    } else if (mode == 'time') {
      config?.integer('thresholdMin');
    } else if (mode != null) {
      err('${c.path}.config.mode', 'must be distance or time');
    }
    config?.boolean('preAlert');
    final expected = <String>{};
    for (final e in c.objList('expect') ?? const <_J>[]) {
      final event = e.str('event');
      if (event != null) {
        if (!kEventNames.contains(event)) {
          err('${e.path}.event', 'unknown event "$event"');
        }
        expected.add(event);
      }
      final nb = e.integer('notBefore');
      final na = e.integer('notAfter');
      e
        ..obj('window')
        ..str('ref');
      if (nb != null && na != null) {
        final max = duration ?? na;
        if (!(0 <= nb && nb <= na && na <= max)) {
          err(
            e.path,
            'need 0 <= notBefore ($nb) <= notAfter ($na) <= '
            'durationS ($max)',
          );
        }
      }
    }
    final forbid = c.list('forbid') ?? const <Object?>[];
    for (var k = 0; k < forbid.length; k++) {
      final event = forbid[k];
      final where = '${c.path}.forbid[$k]';
      if (event is! String || !kEventNames.contains(event)) {
        err(where, 'unknown event "$event"');
      } else if (expected.contains(event)) {
        err(where, 'event "$event" is both expected and forbidden');
      }
    }
  }

  if (gpx == null) {
    return errors;
  }

  // Pair consistency.
  if (sampleCount != null && sampleCount != gpx.pointCount) {
    err(
      'trace.sampleCount',
      'is $sampleCount but the GPX has '
          '${gpx.pointCount} trkpt',
    );
  }
  if (startTime != null &&
      gpx.firstTime != null &&
      startTime != gpx.firstTime) {
    err(
      'trace.startTime',
      'is $startTime but the first trkpt is at '
          '${gpx.firstTime}',
    );
  }
  int? start;
  if (startTime != null) {
    try {
      start = parseIsoUtc(startTime);
    } on FormatException {
      err('trace.startTime', 'must match YYYY-MM-DDTHH:MM:SSZ');
    }
  }
  final all = [for (final s in gpx.segments) ...s];
  if (start != null &&
      duration != null &&
      all.isNotEmpty &&
      all.last - start != duration) {
    err(
      'trace.durationS',
      'is $duration but the last trkpt is at '
          't = ${all.last - start}',
    );
  }
  if (interval != null) {
    for (var i = 0; i < gpx.segments.length; i++) {
      final seg = gpx.segments[i];
      for (var k = 1; k < seg.length; k++) {
        if (seg[k] - seg[k - 1] != interval) {
          errors.add(
            '$gpxLabel:/gpx/trk/trkseg[${i + 1}]/trkpt[${k + 1}]: '
            'interval ${seg[k] - seg[k - 1]} s differs from '
            'sampleIntervalS ($interval)',
          );
        }
      }
    }
  }
  if (gpx.segments.length != gaps.length + 1) {
    err(
      'truth.gpsGaps',
      '${gaps.length} gap(s) need ${gaps.length + 1} '
          'trkseg, the GPX has ${gpx.segments.length}',
    );
  }
  if (start != null) {
    final t0 = start;
    for (var i = 0; i < gaps.length; i++) {
      final (from, to) = gaps[i];
      final inside = all.where((t) => t - t0 >= from && t - t0 < to);
      if (inside.isNotEmpty) {
        err(
          'truth.gpsGaps[$i]',
          'GPX has ${inside.length} sample(s) '
              'inside [$from, $to)',
        );
      }
      if (interval != null && i + 1 < gpx.segments.length) {
        final before = gpx.segments[i];
        final after = gpx.segments[i + 1];
        if (before.isEmpty ||
            after.isEmpty ||
            before.last - t0 + interval != from ||
            after.first - t0 != to) {
          err(
            'truth.gpsGaps[$i]',
            'does not match the break between '
                'trkseg ${i + 1} and ${i + 2}',
          );
        }
      }
    }
  }
  return errors;
}

/// JSON object accessor that records type errors instead of throwing.
final class _J {
  new(this.map, this.path, this.err);

  static _J? root(Object? json, void Function(String, String) err) {
    if (json is! Map<String, Object?>) {
      err('1', 'top level must be a JSON object');
      return null;
    }
    return _J(json, '', err);
  }

  final Map<String, Object?> map;
  final String path;
  final void Function(String where, String message) err;

  String at(String key) => path.isEmpty ? key : '$path.$key';

  bool has(String key) => map.containsKey(key);

  Object? raw(String key) => map[key];

  T? _get<T>(String key, String type) {
    if (!map.containsKey(key)) {
      err(at(key), 'missing required key');
      return null;
    }
    final v = map[key];
    if (v is! T) {
      err(at(key), 'must be $type');
      return null;
    }
    return v;
  }

  String? str(String key) => _get<String>(key, 'a string');

  String? optStr(String key) => has(key) ? str(key) : null;

  int? integer(String key) => _get<int>(key, 'an integer');

  num? number(String key) => _get<num>(key, 'a number');

  bool? boolean(String key) => _get<bool>(key, 'true or false');

  List<Object?>? list(String key) => _get<List<Object?>>(key, 'an array');

  _J? obj(String key) {
    final v = _get<Map<String, Object?>>(key, 'an object');
    return v == null ? null : _J(v, at(key), err);
  }

  List<_J>? objList(String key) {
    final l = list(key);
    if (l == null) {
      return null;
    }
    final out = <_J>[];
    for (var i = 0; i < l.length; i++) {
      final v = l[i];
      if (v is Map<String, Object?>) {
        out.add(_J(v, at('$key[$i]'), err));
      } else {
        err(at('$key[$i]'), 'must be an object');
      }
    }
    return out;
  }
}

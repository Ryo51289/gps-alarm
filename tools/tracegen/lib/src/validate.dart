/// Fixture validation: GPX structure and GPX + expect consistency
/// (spec T02 §7.5, T11 §5.2, T11.1 §3).
library;

import 'dart:convert';

import 'package:tracegen/src/anchor.dart';
import 'package:tracegen/src/fmt.dart';
import 'package:tracegen/src/generator.dart'
    show fallbackEstimates, kExpectedSpeedKmh;
import 'package:tracegen/src/gpx_writer.dart';
import 'package:tracegen/src/paths.dart';
import 'package:tracegen/src/profile.dart';
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
  if ((destination?.has('offsetM') ?? false) &&
      destination?.integer('offsetM') == 0) {
    err('destination.offsetM', 'must be omitted when 0');
  }

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
  final hasOvershoot = truth?.has('overshoot') ?? false;
  if (hasOvershoot) {
    truth?.obj('overshoot')
      ?..integer('closestT')
      ..integer('closestM')
      ..integer('t');
  }
  final hasClosest = truth?.has('closest') ?? false;
  if (hasClosest) {
    truth?.obj('closest')
      ?..integer('t')
      ..integer('straightM')
      ..integer('departT');
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
  final env = _CaseEnv(
    interval: interval,
    duration: duration,
    gapCount: gaps.length,
    hasClosest: hasClosest,
    hasOvershoot: hasOvershoot,
    vehicle: vehicle,
  );
  for (final c in root.objList('cases') ?? const <_J>[]) {
    final caseId = c.str('id');
    if (caseId != null && !caseIds.add(caseId)) {
      err('${c.path}.id', 'duplicate case id "$caseId"');
    }
    _validateCase(c, env);
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

  /// Must-understand rule inside `cases[]` (T11 §1): unknown keys are
  /// errors.
  void allowOnly(Set<String> keys) {
    for (final k in map.keys) {
      if (!keys.contains(k)) {
        err(at(k), 'unknown key (keys inside cases[] must be understood)');
      }
    }
  }

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

final class _CaseEnv {
  const new({
    required this.interval,
    required this.duration,
    required this.gapCount,
    required this.hasClosest,
    required this.hasOvershoot,
    required this.vehicle,
  });

  final int? interval;
  final int? duration;
  final int gapCount;
  final bool hasClosest;

  /// Whether the fixture has `truth.overshoot` (T11.1 §3 V13).
  final bool hasOvershoot;

  /// `trace.vehicle` (default of the vehicle hint).
  final String? vehicle;
}

const Set<String> _filterKeys = {'event', 'reason', 'ringNow', 'cause'};

/// Checks one `cases[i]` of a fixture (T11 §2.2–§2.4, §5.2, §5.3,
/// T11.1 §3).
void _validateCase(_J c, _CaseEnv env) {
  final err = c.err;
  c.allowOnly(const {
    'id',
    'status',
    'testIds',
    'config',
    'samplingModes',
    'policyPhaseSweep',
    'expect',
    'expectAfter',
    'expectFallback',
    'killSweep',
    'expectOutcome',
    'expectSummary',
    'forbid',
    'forbidMatch',
    'forbidAfter',
  });
  final status = c.str('status');
  if (status != null && status != 'draft' && status != 'final') {
    err(c.at('status'), 'must be draft or final');
  }
  final testIds = c.has('testIds') ? c.list('testIds') : null;
  if (testIds != null) {
    final seen = <String>{};
    for (var k = 0; k < testIds.length; k++) {
      final v = testIds[k];
      if (v is! String || !kTestIdPattern.hasMatch(v)) {
        err(c.at('testIds[$k]'), 'must match ${kTestIdPattern.pattern}');
      } else if (!seen.add(v)) {
        err(c.at('testIds[$k]'), 'duplicate test id "$v"');
      }
    }
  }
  if (status == 'final' && (testIds == null || testIds.isEmpty)) {
    err(c.at('testIds'), 'a final case needs a non-empty testIds');
  }

  final checker = _CaseChecker(c, env);
  final config = c.obj('config');
  final cfg = config == null ? null : checker.config(config);
  final paramNames = cfg?.paramNames ?? const <String>[];
  final hasKill = cfg?.hasKill ?? false;
  final hasRelaunch = cfg?.hasRelaunch ?? false;
  List<Object?>? samplingModes;
  if (c.has('samplingModes')) {
    final l = c.list('samplingModes');
    if (l != null &&
        (l.length != 1 ||
            l.single is! String ||
            !kSamplingModes.contains(l.single))) {
      err(c.at('samplingModes'), 'must be ["all"] or ["policy"]');
    }
    samplingModes = l;
  }
  if (c.has('policyPhaseSweep') && (c.boolean('policyPhaseSweep') ?? false)) {
    final interval = env.interval;
    final message = interval == null || cfg == null
        ? null
        : policyPhaseSweepError(
            samplingModes: samplingModes,
            actions: cfg.actions,
            sparseIntervalS: cfg.sparseIntervalS,
            sampleIntervalS: interval,
          );
    if (message != null) {
      err(c.at('policyPhaseSweep'), message);
    }
  }

  // Expectations.
  final expectFilters = <EventFilter>[];
  for (final e in c.objList('expect') ?? const <_J>[]) {
    e.allowOnly(const {
      ..._filterKeys,
      'notBefore',
      'notAfter',
      'window',
      'ref',
    });
    final filter = checker.filterOf(e);
    if (filter != null) {
      expectFilters.add(filter);
    }
    final nb = e.integer('notBefore');
    final na = e.integer('notAfter');
    final window = e.obj('window');
    window?.allowOnly(const {'notBefore', 'notAfter'});
    checker
      ..edge(window?.obj('notBefore'), AnchorUse.window)
      ..edge(window?.obj('notAfter'), AnchorUse.window);
    e.str('ref');
    if (nb != null && na != null) {
      final max = env.duration ?? na;
      if (!(0 <= nb && nb <= na && na <= max)) {
        err(
          e.path,
          'need 0 <= notBefore ($nb) <= notAfter ($na) <= '
          'durationS ($max)',
        );
      }
    }
  }
  final expectAfter = <(EventFilter, AfterRef, int)>[];
  if (c.has('expectAfter')) {
    for (final e in c.objList('expectAfter') ?? const <_J>[]) {
      e.allowOnly(const {..._filterKeys, 'after', 'withinS', 'ref'});
      final filter = checker.filterOf(e);
      final after = checker.timePoint(e.obj('after'), AnchorUse.after);
      final within = checker.pair(e, 'withinS');
      if (within != null && (within.$1 < 0 || within.$1 > within.$2)) {
        err(e.at('withinS'), 'need 0 <= lo <= hi');
      }
      e.str('ref');
      if (filter != null && after != null && within != null) {
        expectAfter.add((filter, after, within.$1));
      }
    }
  }
  if (c.has('expectFallback')) {
    final f = c.obj('expectFallback');
    if (f != null) {
      checker.fallback(f, cfg: cfg, hasKill: hasKill, paramNames: paramNames);
    }
  }
  if (c.has('killSweep')) {
    final k = c.obj('killSweep');
    if (k != null) {
      checker.killSweep(k, cfg);
    }
  }
  if (c.has('expectOutcome')) {
    final v = c.str('expectOutcome');
    if (v != null && !kOutcomes.contains(v)) {
      err(c.at('expectOutcome'), 'unknown outcome "$v"');
    }
  }
  if (c.has('expectSummary')) {
    final s = c.obj('expectSummary');
    s?.allowOnly(const {'vehicleGuess'});
    final v = s?.str('vehicleGuess');
    if (v != null && !kVehicleGuesses.contains(v)) {
      err(s!.at('vehicleGuess'), 'unknown vehicle guess "$v"');
    }
  }

  // Forbidden events.
  final forbid = <String>[];
  final forbidList = c.list('forbid') ?? const <Object?>[];
  for (var k = 0; k < forbidList.length; k++) {
    final event = forbidList[k];
    if (event is! String || !kEventNames.contains(event)) {
      err(c.at('forbid[$k]'), 'unknown event "$event"');
      forbid.add('');
    } else {
      forbid.add(event);
    }
  }
  final forbidMatch = <EventFilter>[];
  if (c.has('forbidMatch')) {
    for (final e in c.objList('forbidMatch') ?? const <_J>[]) {
      e.allowOnly(_filterKeys);
      final filter = checker.filterOf(e);
      if (filter != null) {
        forbidMatch.add(filter);
      }
    }
  }
  final forbidAfter = <(EventFilter, AfterRef)>[];
  if (c.has('forbidAfter')) {
    for (final e in c.objList('forbidAfter') ?? const <_J>[]) {
      e.allowOnly(const {..._filterKeys, 'after'});
      final filter = checker.filterOf(e);
      final after = checker.timePoint(e.obj('after'), AnchorUse.after);
      if (filter != null && after != null) {
        forbidAfter.add((filter, after));
      }
    }
  }

  for (final (anchor, where) in checker.anchors) {
    final message = anchorReferenceError(
      anchor,
      hasKill: hasKill,
      hasRelaunch: hasRelaunch,
      hasClosest: env.hasClosest,
      paramNames: paramNames,
      hasOvershoot: env.hasOvershoot,
    );
    if (message != null) {
      err(where, message);
    }
  }
  for (final issue in checkCaseConsistency(
    expect: expectFilters,
    expectAfter: expectAfter,
    forbid: forbid,
    forbidMatch: forbidMatch,
    forbidAfter: forbidAfter,
  )) {
    err(c.at(issue.path), issue.message);
  }
}

/// Facts of `cases[i].config` needed by the other checks.
typedef _ConfigFacts = ({
  List<String> paramNames,
  bool hasKill,
  int? killT,
  bool hasRelaunch,

  /// Valid `mode`, or null.
  CaseMode? mode,

  /// Valid `thresholdM` / `thresholdMin` of [mode], or null.
  int? threshold,

  /// Valid `vehicleHint`, or null when absent or invalid.
  String? vehicleHint,
  bool vehicleHintInvalid,
  bool hasOsDismiss,
  bool osSimFalse,

  /// `config.actions[].action` values (as written).
  List<Object?> actions,

  /// `params.samplingSparseIntervalS` when it is an integer.
  int? sparseIntervalS,
});

/// Field checks shared by the parts of one case.
final class _CaseChecker {
  new(this.c, this.env);

  final _J c;
  final _CaseEnv env;

  /// Every anchor of the case with its path, for the reference checks.
  final List<(Anchor, String)> anchors = [];

  void Function(String where, String message) get err => c.err;

  void multiple(String where, int v) {
    final interval = env.interval;
    if (interval != null && interval > 0 && v % interval != 0) {
      err(where, 'must be a multiple of sampleIntervalS ($interval)');
    }
  }

  void inTrace(String where, int t) {
    final duration = env.duration;
    if (t < 0 || (duration != null && t > duration)) {
      err(where, 't = $t is outside [0, durationS ($duration)]');
    }
  }

  Anchor? anchorOf(_J o, AnchorUse use) {
    final text = o.str('anchor');
    if (text == null) {
      return null;
    }
    final Anchor anchor;
    try {
      anchor = Anchor.parse(text);
    } on AnchorException catch (x) {
      err(o.at('anchor'), x.message);
      return null;
    }
    final useError = anchorUseError(anchor, use);
    if (useError != null) {
      err(o.at('anchor'), useError);
    }
    if ((anchor.kind == AnchorKind.gpsGapStart ||
            anchor.kind == AnchorKind.gpsGapEnd) &&
        anchor.value >= env.gapCount) {
      err(
        o.at('anchor'),
        'gap index ${anchor.value} out of range (${env.gapCount} gap(s))',
      );
    }
    anchors.add((anchor, o.at('anchor')));
    return anchor;
  }

  /// Window edge `{anchor, offsetS}`; [newKey] = offset must be a multiple
  /// of the interval.
  void edge(_J? o, AnchorUse use, {bool newKey = false}) {
    if (o == null) {
      return;
    }
    o.allowOnly(const {'anchor', 'offsetS'});
    anchorOf(o, use);
    final offset = o.integer('offsetS');
    if (newKey && offset != null) {
      multiple(o.at('offsetS'), offset);
    }
  }

  /// Fixture form of an `At` (T11 §2.3); null when invalid.
  AfterRef? timePoint(_J? p, AnchorUse use) {
    if (p == null) {
      return null;
    }
    p.allowOnly(const {'t', 'anchor', 'offsetS'});
    Anchor? anchor;
    int? offset;
    final anchored = p.has('anchor');
    if (anchored) {
      anchor = anchorOf(p, use);
      offset = p.integer('offsetS');
      if (offset != null) {
        multiple(p.at('offsetS'), offset);
        final interval = env.interval;
        final offsetError = anchor == null || interval == null
            ? null
            : inputRunOffsetError(anchor, use, offset, interval);
        if (offsetError != null) {
          err(p.at('offsetS'), offsetError);
        }
      }
    } else if (p.has('offsetS')) {
      err(p.at('offsetS'), 'only allowed together with anchor');
    }
    int? t;
    if (anchor != null && anchor.isRun) {
      if (p.has('t')) {
        err(p.at('t'), 'a run-time anchor has no t');
      }
    } else if (!anchored || anchor != null) {
      t = p.integer('t');
      if (t != null) {
        multiple(p.at('t'), t);
        inTrace(p.at('t'), t);
      }
    }
    if (anchored) {
      return anchor == null || offset == null
          ? null
          : (anchor: anchor.text, offset: offset);
    }
    return t == null ? null : (anchor: null, offset: t);
  }

  EventFilter? filterOf(_J e) {
    final event = e.str('event');
    if (event == null) {
      return null;
    }
    if (!kEventNames.contains(event)) {
      err(e.at('event'), 'unknown event "$event"');
      return null;
    }
    var ok = true;
    for (final key in const ['reason', 'ringNow', 'cause']) {
      if (e.has(key)) {
        final message = filterError(event, key, e.raw(key));
        if (message != null) {
          err(e.at(key), message);
          ok = false;
        }
      }
    }
    if (!ok) {
      return null;
    }
    return EventFilter(
      event: event,
      reason: e.raw('reason') as String?,
      ringNow: e.raw('ringNow') as bool?,
      cause: e.raw('cause') as String?,
    );
  }

  (int, int)? pair(_J o, String key) {
    final l = o.list(key);
    if (l == null) {
      return null;
    }
    if (l.length != 2 || l[0] is! int || l[1] is! int) {
      err(o.at(key), 'must be an array of 2 integers');
      return null;
    }
    return (l[0]! as int, l[1]! as int);
  }

  _ConfigFacts config(_J config) {
    config.allowOnly(const {
      'mode',
      'thresholdM',
      'thresholdMin',
      'preAlert',
      'vehicleHint',
      'params',
      'battery',
      'actions',
      'kill',
      'relaunch',
      'osDismiss',
      'osSim',
      'osRingMaxS',
    });
    int? range(String key, int lo, int hi) {
      final v = config.integer(key);
      if (v != null && (v < lo || v > hi)) {
        err(config.at(key), 'must be in [$lo, $hi]');
        return null;
      }
      return v;
    }

    void absent(String key, String mode) {
      if (config.has(key)) {
        err(config.at(key), 'not allowed in $mode mode');
      }
    }

    final modeName = config.str('mode');
    CaseMode? mode;
    int? threshold;
    switch (modeName) {
      case null:
        break;
      case 'distance':
        mode = CaseMode.distance;
        threshold = range('thresholdM', 200, 10000);
        absent('thresholdMin', modeName);
      case 'time':
        mode = CaseMode.time;
        threshold = range('thresholdMin', 5, 60);
        absent('thresholdM', modeName);
      case 'smart':
        mode = CaseMode.smart;
        absent('thresholdM', modeName);
        absent('thresholdMin', modeName);
      default:
        err(config.at('mode'), 'must be distance, time or smart');
    }
    config.boolean('preAlert');
    String? vehicleHint;
    var vehicleHintInvalid = false;
    if (config.has('vehicleHint')) {
      final hint = config.str('vehicleHint');
      if (hint != null && kVehicleHints.contains(hint)) {
        vehicleHint = hint;
      } else {
        vehicleHintInvalid = true;
        if (hint != null) {
          err(config.at('vehicleHint'), 'unknown vehicle hint "$hint"');
        }
      }
    }
    final paramNames = <String>[];
    int? sparseIntervalS;
    if (config.has('params')) {
      final params = config.obj('params');
      for (final MapEntry(:key, :value)
          in params?.map.entries ?? const <MapEntry<String, Object?>>[]) {
        paramNames.add(key);
        final where = params!.at(key);
        if (kIntParams.contains(key)) {
          if (value is! int) {
            err(where, 'type I parameter must be a JSON integer');
          } else if (key == 'samplingSparseIntervalS') {
            sparseIntervalS = value;
          }
        } else if (kDoubleParams.contains(key)) {
          if (value is! num || !value.isFinite) {
            err(where, 'must be a number');
          } else if (!hasAtMostParamDecimals(value)) {
            err(where, 'type D parameter has more than 4 decimals');
          }
        } else {
          err(where, 'unknown engine parameter');
        }
      }
    }
    if (config.has('battery')) {
      int? previous;
      for (final b in config.objList('battery') ?? const <_J>[]) {
        b.allowOnly(const {'t', 'levelPct', 'charging'});
        final t = b.integer('t');
        if (t != null) {
          multiple(b.at('t'), t);
          inTrace(b.at('t'), t);
          if (previous != null && t <= previous) {
            err(b.at('t'), 'must increase strictly');
          }
          previous = t;
        }
        final level = b.integer('levelPct');
        if (level != null && (level < 0 || level > 100)) {
          err(b.at('levelPct'), 'must be in [0, 100]');
        }
        b.boolean('charging');
      }
    }
    final actions = <Object?>[];
    if (config.has('actions')) {
      for (final a in config.objList('actions') ?? const <_J>[]) {
        a.allowOnly(const {'at', 'action'});
        actions.add(a.raw('action'));
        final action = a.str('action');
        if (action != null && !kActions.contains(action)) {
          err(a.at('action'), 'unknown action "$action"');
        }
        timePoint(a.obj('at'), AnchorUse.action);
      }
    }
    final hasKill = config.has('kill');
    int? killT;
    if (hasKill) {
      final kill = config.obj('kill');
      timePoint(kill, AnchorUse.kill);
      final t = kill?.raw('t');
      killT = t is int ? t : null;
    }
    final hasRelaunch = config.has('relaunch');
    String? fallbackStatus;
    if (hasRelaunch) {
      final r = config.obj('relaunch');
      r?.allowOnly(const {'at', 'fallbackStatus'});
      if (!hasKill) {
        err(config.at('relaunch'), 'needs config.kill');
      }
      final at = r?.obj('at');
      timePoint(at, AnchorUse.relaunch);
      final t = at?.raw('t');
      if (t is int && killT != null && t <= killT) {
        err(at!.at('t'), 'must be after config.kill (t = $killT)');
      }
      fallbackStatus = r?.str('fallbackStatus');
      if (fallbackStatus != null &&
          !kFallbackStatuses.contains(fallbackStatus)) {
        err(r!.at('fallbackStatus'), 'unknown status "$fallbackStatus"');
      }
    }
    if (config.has('osDismiss')) {
      final d = config.obj('osDismiss');
      d?.allowOnly(const {'offsetS'});
      if (fallbackStatus != 'auto') {
        err(
          config.at('osDismiss'),
          'needs config.relaunch with fallbackStatus auto',
        );
      }
      final offset = d?.integer('offsetS');
      if (d != null && offset != null) {
        if (offset <= 0) {
          err(d.at('offsetS'), 'must be > 0');
        }
        multiple(d.at('offsetS'), offset);
      }
    }
    var osSimFalse = false;
    if (config.has('osSim')) {
      final osSim = config.boolean('osSim');
      osSimFalse = osSim == false;
      if (osSim == false && fallbackStatus == 'auto') {
        err(
          config.at('osSim'),
          'relaunch with fallbackStatus auto needs osSim',
        );
      }
    }
    if (config.has('osRingMaxS')) {
      final v = config.integer('osRingMaxS');
      if (v != null && v <= 0) {
        err(config.at('osRingMaxS'), 'must be > 0');
      }
    }
    return (
      paramNames: paramNames,
      hasKill: hasKill,
      killT: killT,
      hasRelaunch: hasRelaunch,
      mode: mode,
      threshold: threshold,
      vehicleHint: vehicleHint,
      vehicleHintInvalid: vehicleHintInvalid,
      hasOsDismiss: config.has('osDismiss'),
      osSimFalse: osSimFalse,
      actions: actions,
      sparseIntervalS: sparseIntervalS,
    );
  }

  /// `killSweep` (T11.1 §2, §3 V5-V10).
  void killSweep(_J k, _ConfigFacts? cfg) {
    k.allowOnly(kKillSweepKeys);
    if (cfg != null) {
      final conflict = killSweepConflict(
        hasKill: cfg.hasKill,
        hasRelaunch: cfg.hasRelaunch,
        hasOsDismiss: cfg.hasOsDismiss,
        osSimFalse: cfg.osSimFalse,
      );
      if (conflict != null) {
        err(k.path, conflict);
      }
    }
    final from = k.obj('from');
    timePoint(from, AnchorUse.killSweep);
    final fromT = from?.raw('t');
    final interval = env.interval;
    if (fromT is int && interval != null && fromT < interval) {
      err(from!.at('t'), 'must be >= sampleIntervalS ($interval)');
    }
    final everyS = k.integer('everyS');
    if (everyS != null) {
      if (everyS <= 0) {
        err(k.at('everyS'), 'must be > 0');
      } else {
        multiple(k.at('everyS'), everyS);
      }
    }
    timePoint(k.obj('notAfter'), AnchorUse.killSweep);
    timePoint(k.obj('earlyFrom'), AnchorUse.killSweep);
    if (k.has('statsOnly')) {
      k.boolean('statsOnly');
    }
  }

  /// `expectFallback` against the formula of T11.1 §4 (T11 §5.3).
  void fallback(
    _J f, {
    required _ConfigFacts? cfg,
    required bool hasKill,
    required List<String> paramNames,
  }) {
    final killT = cfg?.killT;
    f.allowOnly(const {'asOfT', 'notBefore', 'notAfter', 'window', 'ref'});
    if (!hasKill) {
      err(f.path, 'needs config.kill');
    }
    final lagParams = paramNames.where(kFallbackFormulaParams.contains);
    if (lagParams.isNotEmpty) {
      err(
        f.path,
        'cannot be checked when params override ${lagParams.join(', ')}',
      );
    }
    final asOfT = f.integer('asOfT');
    final nb = f.integer('notBefore');
    final na = f.integer('notAfter');
    f.str('ref');
    final w = f.obj('window');
    if (w == null) {
      return;
    }
    w.allowOnly(const {
      'modeAt',
      'modeAtT',
      'killT',
      'estimateT',
      'asOfStraightM',
      'hintEstimateT',
      'toleranceS',
    });
    edge(w.obj('modeAt'), AnchorUse.modeAt, newKey: true);
    final modeAtT = w.integer('modeAtT');
    final wKill = w.integer('killT');
    final estimate = w.integer('estimateT');
    var asOfStraightM = w.integer('asOfStraightM');
    if (asOfStraightM != null && asOfStraightM < 0) {
      err(w.at('asOfStraightM'), 'must be >= 0');
      asOfStraightM = null;
    }
    final hintEstimate = w.integer('hintEstimateT');
    final tol = pair(w, 'toleranceS');
    if (killT != null && wKill != null && wKill != killT) {
      err(w.at('killT'), 'is $wKill but config.kill.t is $killT');
    }
    final interval = env.interval;
    if (wKill != null &&
        interval != null &&
        asOfT != null &&
        asOfT != wKill - interval) {
      err(
        f.at('asOfT'),
        'must be killT - sampleIntervalS (${wKill - interval})',
      );
    }
    if (tol != null && tol.$1 > tol.$2) {
      err(w.at('toleranceS'), 'need lo <= hi');
    }
    // Recompute every number from the inputs only (T11.1 §4); a missing or
    // invalid input skips the recomputation (its own error is reported).
    final mode = cfg?.mode;
    final threshold = cfg?.threshold;
    final hint =
        cfg?.vehicleHint ??
        (cfg != null && cfg.vehicleHintInvalid ? null : env.vehicle);
    final duration = env.duration;
    if (modeAtT == null ||
        wKill == null ||
        asOfStraightM == null ||
        tol == null ||
        mode == null ||
        (mode != CaseMode.smart && threshold == null) ||
        hint == null ||
        !kExpectedSpeedKmh.containsKey(hint) ||
        interval == null ||
        duration == null) {
      return;
    }
    final want = fallbackEstimates(
      mode: mode,
      threshold: threshold,
      hint: hint,
      modeAtT: modeAtT,
      killT: wKill,
      asOfStraightM: asOfStraightM,
      sampleIntervalS: interval,
      durationS: duration,
      toleranceLo: tol.$1,
      toleranceHi: tol.$2,
    );
    if (estimate != null && estimate != want.estimateT) {
      err(
        w.at('estimateT'),
        'is $estimate but T11 §5.3 gives ${want.estimateT}',
      );
    }
    if (hintEstimate != null && hintEstimate != want.hintEstimateT) {
      err(
        w.at('hintEstimateT'),
        'is $hintEstimate but T11 §5.3 gives ${want.hintEstimateT}',
      );
    }
    if (nb != null && nb != want.notBefore) {
      err(
        f.at('notBefore'),
        'is $nb but min(estimateT, hintEstimateT) + toleranceS[0] = '
        '${want.notBefore}',
      );
    }
    if (na != null && na != want.notAfter) {
      err(
        f.at('notAfter'),
        'is $na but estimateT + toleranceS[1] = ${want.notAfter}',
      );
    }
  }
}

// Independent recomputation of every resolved time in a committed
// `expect.json` (T11 TG32, tester).
//
// The oracle re-derives each number from the per-tick motion truth
// (`TruthState.s`, straight-line distance to the effective destination) and
// from the GPX itself (gap edges), using its own anchor parser, its own
// first-tick search and its own copy of the T11 §5.3 formula. It only shares
// the motion simulation with the generator, never the anchor resolution, the
// writer or the validator, so a bug in `resolveCase`/`writeExpect` shows up
// as a mismatch.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:tracegen/tracegen.dart';

/// One recomputed number: [expected] (oracle) vs [actual] (fixture).
final class Row {
  const new(this.where, this.expr, this.expected, this.actual);

  /// `profile/case field` or `profile truth.field`.
  final String where;

  /// How the oracle obtained [expected] (anchor expression or formula).
  final String expr;
  final int? expected;
  final int? actual;

  bool get ok => expected == actual;

  @override
  String toString() {
    final flag = ok ? '' : '  <-- MISMATCH';
    return '$where: $expr = $expected, fixture has $actual$flag';
  }
}

/// Gap edges `(fromT, toT)` read straight from the GPX: a new `trkseg`
/// starts after every gap (fixtures README §2).
List<(int, int)> gapsFromGpx(String gpx, int startEpochS, int intervalS) {
  final segments = gpx.split('<trkseg>').skip(1).map((seg) {
    final times = RegExp('<time>([^<]+)</time>').allMatches(seg);
    return [
      for (final m in times)
        DateTime.parse(m.group(1)!).millisecondsSinceEpoch ~/ 1000 -
            startEpochS,
    ];
  }).toList();
  return [
    for (var i = 0; i + 1 < segments.length; i++)
      (segments[i].last + intervalS, segments[i + 1].first),
  ];
}

final class Oracle {
  new({
    required this.id,
    required this.fixture,
    required this.truth,
    required this.gpxGaps,
  });

  /// Loads the committed pair [id] and the motion truth of its profile.
  factory load(String id, {required Directory data, required Directory fix}) {
    final (profile, route) = ProfileRepository(data).load(id);
    final truth = buildTrace(profile, route).truth;
    final fixture = jsonDecode(
      File('${fix.path}/$id.expect.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final trace = fixture['trace']! as Map<String, Object?>;
    final start =
        DateTime.parse(trace['startTime']! as String).millisecondsSinceEpoch ~/
        1000;
    final gpx = File('${fix.path}/$id.gpx').readAsStringSync();
    return Oracle(
      id: id,
      fixture: fixture,
      truth: truth,
      gpxGaps: gapsFromGpx(gpx, start, trace['sampleIntervalS']! as int),
    );
  }

  final String id;
  final Map<String, Object?> fixture;
  final TraceTruth truth;
  final List<(int, int)> gpxGaps;

  Map<String, Object?> get _trace => fixture['trace']! as Map<String, Object?>;
  Map<String, Object?> get _truth => fixture['truth']! as Map<String, Object?>;
  int get durationS => _trace['durationS']! as int;
  int get intervalS => _trace['sampleIntervalS']! as int;

  List<TruthState> get _states => truth.states;
  double get _sDest => truth.destinationRouteM;
  List<double> get _straight => truth.straightM;

  int? _first(bool Function(int j) test) {
    for (var j = 0; j < _states.length; j++) {
      if (test(j)) {
        return _states[j].t;
      }
    }
    return null;
  }

  /// First tick with `s >= sDest` (README §3 `truth.arrivalT`).
  int get arrivalT => _first((j) => _states[j].s >= _sDest)!;

  /// README §3 `truth.overshoot.t` (null when the route ends < 1 km after
  /// the destination).
  ({int closestT, int closestM, int t})? get overshoot {
    if (truth.routeLengthM - _sDest < 1000) {
      return null;
    }
    var c = 0;
    for (var j = 1; j < _straight.length; j++) {
      if (_straight[j] < _straight[c]) {
        c = j;
      }
    }
    var departT = arrivalT;
    for (final st in _states) {
      if (st.s == _sDest) {
        departT = st.t;
      }
    }
    final t = _first(
      (j) =>
          _states[j].t > departT &&
          _states[j].s > _sDest &&
          _straight[j] >= _straight[c] + 1000,
    );
    return t == null
        ? null
        : (closestT: _states[c].t, closestM: _straight[c].round(), t: t);
  }

  /// README §3 / T11 §4.2 `truth.closest`.
  ({int t, int straightM, int departT})? get closest {
    if (!(fixture['destination']! as Map).containsKey('offsetM')) {
      return null;
    }
    var jMin = 0;
    for (var j = 1; j < _straight.length; j++) {
      if (_straight[j] < _straight[jMin]) {
        jMin = j;
      }
    }
    final dMin = _straight[jMin];
    final need = max(500, 0.5 * dMin);
    int? departT;
    for (var j = jMin + 1; j < _straight.length; j++) {
      if (_straight[j] >= dMin + need) {
        departT = _states[j].t;
        break;
      }
    }
    return (t: _states[jMin].t, straightM: dMin.round(), departT: departT!);
  }

  int? routeWithin(int x) => _first((j) => _sDest - _states[j].s <= x);

  int? straightWithin(int x) => _first((j) => _straight[j] <= x);

  /// Resolves a static anchor; [killT] for `kill`.
  int resolve(String anchor, {int? killT}) {
    final gap = RegExp(r'^gpsGap\[(\d+)\]\.(start|end)$').firstMatch(anchor);
    final within = RegExp(r'^(route|straight)<=(\d+)$').firstMatch(anchor);
    if (gap != null) {
      final g = gpxGaps[int.parse(gap.group(1)!)];
      return gap.group(2) == 'start' ? g.$1 : g.$2;
    }
    if (within != null) {
      final x = int.parse(within.group(2)!);
      return (within.group(1) == 'route' ? routeWithin(x) : straightWithin(x))!;
    }
    return switch (anchor) {
      'start' => 0,
      'end' => _states.last.t,
      'arrival' => arrivalT,
      'overshoot' => overshoot!.t,
      'closest' => closest!.t,
      'closest.departT' => closest!.departT,
      'kill' => killT!,
      _ => throw ArgumentError('not a static anchor: $anchor'),
    };
  }

  static bool isRun(String anchor) =>
      anchor.startsWith('event:') ||
      anchor == 'relaunch' ||
      anchor == 'osFallbackFired';

  static String exprOf(String anchor, int offset) => offset == 0
      ? anchor
      : offset > 0
      ? '$anchor + $offset'
      : '$anchor − ${-offset}';

  /// Every recomputed number of the fixture.
  List<Row> rows() {
    final out = <Row>[..._truthRows()];
    for (final c in (fixture['cases']! as List).cast<Map<String, Object?>>()) {
      out.addAll(_caseRows(c));
    }
    return out;
  }

  List<Row> _truthRows() {
    final out = <Row>[
      Row(
        '$id trace.durationS',
        'last tick',
        _states.last.t,
        _trace['durationS'] as int?,
      ),
      Row(
        '$id truth.arrivalT',
        'first tick s >= sDest',
        arrivalT,
        _truth['arrivalT'] as int?,
      ),
      Row(
        '$id truth.destinationRouteM',
        'round(sDest)',
        _sDest.round(),
        _truth['destinationRouteM'] as int?,
      ),
    ];
    final gaps = (_truth['gpsGaps']! as List).cast<Map<String, Object?>>();
    out.add(
      Row(
        '$id truth.gpsGaps.length',
        'GPX trkseg - 1',
        gpxGaps.length,
        gaps.length,
      ),
    );
    for (var i = 0; i < min(gaps.length, gpxGaps.length); i++) {
      out
        ..add(
          Row(
            '$id truth.gpsGaps[$i].fromT',
            'GPX: last t of trkseg ${i + 1} + I',
            gpxGaps[i].$1,
            gaps[i]['fromT'] as int?,
          ),
        )
        ..add(
          Row(
            '$id truth.gpsGaps[$i].toT',
            'GPX: first t of trkseg ${i + 2}',
            gpxGaps[i].$2,
            gaps[i]['toT'] as int?,
          ),
        );
    }
    final ov = overshoot;
    final fov = _truth['overshoot'] as Map<String, Object?>?;
    out.add(
      Row(
        '$id truth.overshoot?',
        'exists',
        ov == null ? 0 : 1,
        fov == null ? 0 : 1,
      ),
    );
    if (ov != null && fov != null) {
      out
        ..add(
          Row(
            '$id truth.overshoot.closestT',
            'argmin straight',
            ov.closestT,
            fov['closestT'] as int?,
          ),
        )
        ..add(
          Row(
            '$id truth.overshoot.closestM',
            'round(min straight)',
            ov.closestM,
            fov['closestM'] as int?,
          ),
        )
        ..add(
          Row(
            '$id truth.overshoot.t',
            'first tick after leaving with straight >= min + 1000',
            ov.t,
            fov['t'] as int?,
          ),
        );
    }
    final cl = closest;
    final fcl = _truth['closest'] as Map<String, Object?>?;
    out.add(
      Row(
        '$id truth.closest?',
        'exists',
        cl == null ? 0 : 1,
        fcl == null ? 0 : 1,
      ),
    );
    if (cl != null && fcl != null) {
      out
        ..add(
          Row('$id truth.closest.t', 'argmin straight', cl.t, fcl['t'] as int?),
        )
        ..add(
          Row(
            '$id truth.closest.straightM',
            'round(dMin)',
            cl.straightM,
            fcl['straightM'] as int?,
          ),
        )
        ..add(
          Row(
            '$id truth.closest.departT',
            'first tick > t with straight >= dMin + max(500, dMin/2)',
            cl.departT,
            fcl['departT'] as int?,
          ),
        );
    }
    final milestones = fixture['milestones']! as Map<String, Object?>;
    for (final m
        in (milestones['distance']! as List).cast<Map<String, Object?>>()) {
      final x = m['thresholdM']! as int;
      out.add(
        Row(
          '$id milestones.distance[$x].routeT',
          'route<=$x',
          routeWithin(x),
          m['routeT'] as int?,
        ),
      );
      final straightT = _straight.first <= x ? null : straightWithin(x);
      out.add(
        Row(
          '$id milestones.distance[$x].straightT',
          'straight<=$x (null if never/always)',
          straightT,
          m['straightT'] as int?,
        ),
      );
    }
    for (final m
        in (milestones['time']! as List).cast<Map<String, Object?>>()) {
      final n = m['beforeArrivalMin']! as int;
      out.add(
        Row(
          '$id milestones.time[$n].t',
          'A − ${60 * n}',
          arrivalT - 60 * n,
          m['t'] as int?,
        ),
      );
    }
    return out;
  }

  List<Row> _caseRows(Map<String, Object?> c) {
    final where = '$id/${c['id']}';
    final out = <Row>[];
    final config = c['config']! as Map<String, Object?>;
    final kill = config['kill'] as Map<String, Object?>?;
    int? killT;

    // `At`: static anchors carry t = anchor + offsetS (no clamp, in
    // [0, durationS]); run anchors carry no t.
    void at(String field, Map<String, Object?>? p) {
      if (p == null) {
        return;
      }
      final anchor = p['anchor'] as String?;
      if (anchor == null) {
        // Literal {t}: only a range check.
        final t = p['t']! as int;
        out.add(
          Row('$where $field.t', 'literal in [0, D]', t.clamp(0, durationS), t),
        );
        return;
      }
      final off = p['offsetS']! as int;
      if (isRun(anchor)) {
        out.add(
          Row(
            '$where $field.t',
            'run anchor ${exprOf(anchor, off)}: no t',
            null,
            p['t'] as int?,
          ),
        );
        return;
      }
      final t = resolve(anchor, killT: killT) + off;
      out
        ..add(Row('$where $field.t', exprOf(anchor, off), t, p['t'] as int?))
        ..add(
          Row(
            '$where $field.t in [0, D]',
            '0 <= t <= $durationS',
            1,
            t >= 0 && t <= durationS ? 1 : 0,
          ),
        );
    }

    at('config.kill', kill);
    killT = kill?['t'] as int?;
    final relaunch = config['relaunch'] as Map<String, Object?>?;
    at('config.relaunch.at', relaunch?['at'] as Map<String, Object?>?);
    final actions = (config['actions'] as List?)?.cast<Map<String, Object?>>();
    for (var i = 0; i < (actions?.length ?? 0); i++) {
      at('config.actions[$i].at', actions![i]['at']! as Map<String, Object?>);
    }

    final expect = (c['expect']! as List).cast<Map<String, Object?>>();
    for (var i = 0; i < expect.length; i++) {
      final e = expect[i];
      final w = e['window']! as Map<String, Object?>;
      for (final edge in ['notBefore', 'notAfter']) {
        final p = w[edge]! as Map<String, Object?>;
        final anchor = p['anchor']! as String;
        final off = p['offsetS']! as int;
        final v = (resolve(anchor, killT: killT) + off).clamp(0, durationS);
        out.add(
          Row(
            '$where expect[$i] ${e['event']}${_filterText(e)}.$edge',
            'clamp(${exprOf(anchor, off)}, 0, D)',
            v,
            e[edge] as int?,
          ),
        );
      }
    }
    for (final (key, list) in [
      ('expectAfter', c['expectAfter'] as List?),
      ('forbidAfter', c['forbidAfter'] as List?),
    ]) {
      final items = list?.cast<Map<String, Object?>>() ?? const [];
      for (var i = 0; i < items.length; i++) {
        at('$key[$i].after', items[i]['after']! as Map<String, Object?>);
      }
    }

    final f = c['expectFallback'] as Map<String, Object?>?;
    if (f != null) {
      final w = f['window']! as Map<String, Object?>;
      final modeAt = w['modeAt']! as Map<String, Object?>;
      final tol = (w['toleranceS']! as List).cast<int>();
      final anchor = modeAt['anchor']! as String;
      final off = modeAt['offsetS']! as int;
      final modeAtT = resolve(anchor, killT: killT) + off;
      final k = killT!;
      // T11 §5.3, written out again (integers only).
      final lead = modeAtT - k - 600;
      final early = min(1800, (lead < 0 ? 0 : lead) ~/ 10);
      final e = modeAtT + 30 - early;
      final p = '$where expectFallback';
      out.addAll([
        Row(
          '$p.window.modeAtT',
          exprOf(anchor, off),
          modeAtT,
          w['modeAtT'] as int?,
        ),
        Row('$p.window.killT', 'config.kill.t', k, w['killT'] as int?),
        Row(
          '$p.window.estimateT',
          'modeAtT + 30 − min(1800, max(0, modeAtT − killT − 600) ~/ 10) '
              '(early = $early)',
          e,
          w['estimateT'] as int?,
        ),
        Row('$p.asOfT', 'killT − I', k - intervalS, f['asOfT'] as int?),
        Row(
          '$p.notBefore',
          'clamp(E + ${tol[0]}, 0, D)',
          (e + tol[0]).clamp(0, durationS),
          f['notBefore'] as int?,
        ),
        Row(
          '$p.notAfter',
          'clamp(E + ${tol[1]}, 0, D)',
          (e + tol[1]).clamp(0, durationS),
          f['notAfter'] as int?,
        ),
      ]);
    }
    return out;
  }

  static String _filterText(Map<String, Object?> e) => [
    if (e.containsKey('reason')) '/${e['reason']}',
    if (e.containsKey('ringNow')) '/ringNow=${e['ringNow']}',
    if (e.containsKey('cause')) '/${e['cause']}',
  ].join();
}

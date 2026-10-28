/// Simulated location sensor: correlated noise, missing speed, GPS gaps and
/// outliers (spec T02 §6.4).
library;

import 'dart:math' show max, sqrt;

import 'package:tracegen/src/geo.dart';
import 'package:tracegen/src/motion.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/rng.dart';

/// One emitted location sample.
final class Observation {
  const new({
    required this.t,
    required this.pos,
    required this.accM,
    this.speedMps,
  });

  final int t;
  final LatLng pos;
  final double accM;

  /// Null when the device reports no speed.
  final double? speedMps;
}

enum OutlierKind { random, scripted }

final class OutlierRecord {
  const new({required this.t, required this.kind, required this.errorM});

  final int t;
  final OutlierKind kind;

  /// Rounded distance between the reported and the true position, metres.
  final int errorM;
}

/// GPS outage: no sample with `fromT <= t < toT`.
final class GapRecord {
  const new({required this.fromT, required this.toT});

  final int fromT;

  /// Exclusive: the first sample after the outage is at [toT].
  final int toT;

  bool contains(int t) => t >= fromT && t < toT;
}

/// Reported position and accuracy of one scripted outlier tick.
final class ScriptedPoint {
  const new({required this.pos, required this.accM});

  final LatLng pos;
  final double accM;
}

final class SensorResult {
  const new({required this.observations, required this.outliers});

  /// Emitted samples in time order (none inside gaps).
  final List<Observation> observations;

  /// Outliers in time order (only for emitted samples).
  final List<OutlierRecord> outliers;
}

/// Runs the sensor model over [truth] (one state per tick).
///
/// Every tick draws the same number of random values, so gaps and scripted
/// outliers never change the noise of the other ticks.
SensorResult simulateSensor({
  required List<TruthState> truth,
  required NoiseSpec noise,
  required int noiseSeed,
  List<GapRecord> gaps = const [],
  Map<int, ScriptedPoint> scripted = const {},
}) {
  final noiseRng = SplitMix64.stream(noiseSeed, kNoiseStream);
  final outlierRng = SplitMix64.stream(noiseSeed, kOutlierStream);
  final sigma = noise.sigmaM;
  final innovation = sqrt(1 - noise.rho * noise.rho);

  var eE = sigma * noiseRng.nextGaussian();
  var eN = sigma * noiseRng.nextGaussian();

  final observations = <Observation>[];
  final outliers = <OutlierRecord>[];
  for (final state in truth) {
    final gE = noiseRng.nextGaussian();
    final gN = noiseRng.nextGaussian();
    final uAcc = noiseRng.nextDouble();
    final gS = noiseRng.nextGaussian();
    final uMiss = noiseRng.nextDouble();
    eE = noise.rho * eE + innovation * sigma * gE;
    eN = noise.rho * eN + innovation * sigma * gN;

    final uOut = outlierRng.nextDouble();
    final uMag = outlierRng.nextDouble();
    final dE = outlierRng.nextGaussian();
    final dN = outlierRng.nextGaussian();

    var pos = offsetM(state.pos, eE, eN);
    var acc = max(noise.accMinM, sigma * 1.5 * (0.8 + 0.4 * uAcc));
    final speed = uMiss < noise.speedMissingRate
        ? null
        : max<double>(0, state.speedMps + noise.speedSigmaMps * gS);

    OutlierKind? outlier;
    if (noise.outlierRate > 0 && uOut < noise.outlierRate) {
      final r = sqrt(dE * dE + dN * dN);
      final ux = r < 1e-9 ? 1.0 : dE / r;
      final uy = r < 1e-9 ? 0.0 : dN / r;
      final m =
          noise.outlierMinM + (noise.outlierMaxM - noise.outlierMinM) * uMag;
      pos = offsetM(state.pos, ux * m, uy * m);
      outlier = OutlierKind.random;
    }
    final script = scripted[state.t];
    if (script != null) {
      pos = script.pos;
      acc = script.accM;
      outlier = OutlierKind.scripted;
    }
    if (gaps.any((g) => g.contains(state.t))) {
      continue;
    }
    observations.add(
      Observation(t: state.t, pos: pos, accM: acc, speedMps: speed),
    );
    if (outlier != null) {
      outliers.add(
        OutlierRecord(
          t: state.t,
          kind: outlier,
          errorM: distanceM(pos, state.pos).round(),
        ),
      );
    }
  }
  return SensorResult(
    observations: List.unmodifiable(observations),
    outliers: List.unmodifiable(outliers),
  );
}

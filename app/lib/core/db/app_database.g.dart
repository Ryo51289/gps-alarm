// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TripsTable extends Trips with TableInfo<$TripsTable, TripRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TripsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationNameMeta = const VerificationMeta(
    'destinationName',
  );
  @override
  late final GeneratedColumn<String> destinationName = GeneratedColumn<String>(
    'destination_name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationDetailMeta = const VerificationMeta(
    'destinationDetail',
  );
  @override
  late final GeneratedColumn<String> destinationDetail =
      GeneratedColumn<String>(
        'destination_detail',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  late final GeneratedColumnWithTypeConverter<DestinationKind, String>
  destinationKind = GeneratedColumn<String>(
    'destination_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<DestinationKind>($TripsTable.$converterdestinationKind);
  static const VerificationMeta _destLatMeta = const VerificationMeta(
    'destLat',
  );
  @override
  late final GeneratedColumn<double> destLat = GeneratedColumn<double>(
    'dest_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destLngMeta = const VerificationMeta(
    'destLng',
  );
  @override
  late final GeneratedColumn<double> destLng = GeneratedColumn<double>(
    'dest_lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DestinationSource, String>
  destSource = GeneratedColumn<String>(
    'dest_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<DestinationSource>($TripsTable.$converterdestSource);
  @override
  late final GeneratedColumnWithTypeConverter<AlarmModeMsg, String> mode =
      GeneratedColumn<String>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AlarmModeMsg>($TripsTable.$convertermode);
  static const VerificationMeta _distanceThresholdMMeta =
      const VerificationMeta('distanceThresholdM');
  @override
  late final GeneratedColumn<int> distanceThresholdM = GeneratedColumn<int>(
    'distance_threshold_m',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timeThresholdMinMeta = const VerificationMeta(
    'timeThresholdMin',
  );
  @override
  late final GeneratedColumn<int> timeThresholdMin = GeneratedColumn<int>(
    'time_threshold_min',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preAlertEnabledMeta = const VerificationMeta(
    'preAlertEnabled',
  );
  @override
  late final GeneratedColumn<bool> preAlertEnabled = GeneratedColumn<bool>(
    'pre_alert_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pre_alert_enabled" IN (0, 1))',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<VehicleKindMsg, String>
  vehicleHint = GeneratedColumn<String>(
    'vehicle_hint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<VehicleKindMsg>($TripsTable.$convertervehicleHint);
  static const VerificationMeta _simulatedMeta = const VerificationMeta(
    'simulated',
  );
  @override
  late final GeneratedColumn<bool> simulated = GeneratedColumn<bool>(
    'simulated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("simulated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TripOutcomeMsg?, String> result =
      GeneratedColumn<String>(
        'result',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<TripOutcomeMsg?>($TripsTable.$converterresultn);
  @override
  late final GeneratedColumnWithTypeConverter<EndReasonMsg?, String> endReason =
      GeneratedColumn<String>(
        'end_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<EndReasonMsg?>($TripsTable.$converterendReasonn);
  static const VerificationMeta _alarmAtMeta = const VerificationMeta(
    'alarmAt',
  );
  @override
  late final GeneratedColumn<int> alarmAt = GeneratedColumn<int>(
    'alarm_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AlarmReasonMsg?, String>
  alarmReason = GeneratedColumn<String>(
    'alarm_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<AlarmReasonMsg?>($TripsTable.$converteralarmReasonn);
  static const VerificationMeta _dismissedAtMeta = const VerificationMeta(
    'dismissedAt',
  );
  @override
  late final GeneratedColumn<int> dismissedAt = GeneratedColumn<int>(
    'dismissed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snoozeCountMeta = const VerificationMeta(
    'snoozeCount',
  );
  @override
  late final GeneratedColumn<int> snoozeCount = GeneratedColumn<int>(
    'snooze_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _travelledMMeta = const VerificationMeta(
    'travelledM',
  );
  @override
  late final GeneratedColumn<int> travelledM = GeneratedColumn<int>(
    'travelled_m',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<VehicleKindMsg?, String>
  vehicleGuess = GeneratedColumn<String>(
    'vehicle_guess',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<VehicleKindMsg?>($TripsTable.$convertervehicleGuessn);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    destinationName,
    destinationDetail,
    destinationKind,
    destLat,
    destLng,
    destSource,
    mode,
    distanceThresholdM,
    timeThresholdMin,
    preAlertEnabled,
    vehicleHint,
    simulated,
    startedAt,
    endedAt,
    result,
    endReason,
    alarmAt,
    alarmReason,
    dismissedAt,
    snoozeCount,
    travelledM,
    vehicleGuess,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'trips';
  @override
  VerificationContext validateIntegrity(
    Insertable<TripRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('destination_name')) {
      context.handle(
        _destinationNameMeta,
        destinationName.isAcceptableOrUnknown(
          data['destination_name']!,
          _destinationNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationNameMeta);
    }
    if (data.containsKey('destination_detail')) {
      context.handle(
        _destinationDetailMeta,
        destinationDetail.isAcceptableOrUnknown(
          data['destination_detail']!,
          _destinationDetailMeta,
        ),
      );
    }
    if (data.containsKey('dest_lat')) {
      context.handle(
        _destLatMeta,
        destLat.isAcceptableOrUnknown(data['dest_lat']!, _destLatMeta),
      );
    } else if (isInserting) {
      context.missing(_destLatMeta);
    }
    if (data.containsKey('dest_lng')) {
      context.handle(
        _destLngMeta,
        destLng.isAcceptableOrUnknown(data['dest_lng']!, _destLngMeta),
      );
    } else if (isInserting) {
      context.missing(_destLngMeta);
    }
    if (data.containsKey('distance_threshold_m')) {
      context.handle(
        _distanceThresholdMMeta,
        distanceThresholdM.isAcceptableOrUnknown(
          data['distance_threshold_m']!,
          _distanceThresholdMMeta,
        ),
      );
    }
    if (data.containsKey('time_threshold_min')) {
      context.handle(
        _timeThresholdMinMeta,
        timeThresholdMin.isAcceptableOrUnknown(
          data['time_threshold_min']!,
          _timeThresholdMinMeta,
        ),
      );
    }
    if (data.containsKey('pre_alert_enabled')) {
      context.handle(
        _preAlertEnabledMeta,
        preAlertEnabled.isAcceptableOrUnknown(
          data['pre_alert_enabled']!,
          _preAlertEnabledMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_preAlertEnabledMeta);
    }
    if (data.containsKey('simulated')) {
      context.handle(
        _simulatedMeta,
        simulated.isAcceptableOrUnknown(data['simulated']!, _simulatedMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('alarm_at')) {
      context.handle(
        _alarmAtMeta,
        alarmAt.isAcceptableOrUnknown(data['alarm_at']!, _alarmAtMeta),
      );
    }
    if (data.containsKey('dismissed_at')) {
      context.handle(
        _dismissedAtMeta,
        dismissedAt.isAcceptableOrUnknown(
          data['dismissed_at']!,
          _dismissedAtMeta,
        ),
      );
    }
    if (data.containsKey('snooze_count')) {
      context.handle(
        _snoozeCountMeta,
        snoozeCount.isAcceptableOrUnknown(
          data['snooze_count']!,
          _snoozeCountMeta,
        ),
      );
    }
    if (data.containsKey('travelled_m')) {
      context.handle(
        _travelledMMeta,
        travelledM.isAcceptableOrUnknown(data['travelled_m']!, _travelledMMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TripRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TripRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      destinationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_name'],
      )!,
      destinationDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_detail'],
      ),
      destinationKind: $TripsTable.$converterdestinationKind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}destination_kind'],
        )!,
      ),
      destLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dest_lat'],
      )!,
      destLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dest_lng'],
      )!,
      destSource: $TripsTable.$converterdestSource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}dest_source'],
        )!,
      ),
      mode: $TripsTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mode'],
        )!,
      ),
      distanceThresholdM: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distance_threshold_m'],
      ),
      timeThresholdMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_threshold_min'],
      ),
      preAlertEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pre_alert_enabled'],
      )!,
      vehicleHint: $TripsTable.$convertervehicleHint.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}vehicle_hint'],
        )!,
      ),
      simulated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}simulated'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      ),
      result: $TripsTable.$converterresultn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}result'],
        ),
      ),
      endReason: $TripsTable.$converterendReasonn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}end_reason'],
        ),
      ),
      alarmAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}alarm_at'],
      ),
      alarmReason: $TripsTable.$converteralarmReasonn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}alarm_reason'],
        ),
      ),
      dismissedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dismissed_at'],
      ),
      snoozeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snooze_count'],
      )!,
      travelledM: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}travelled_m'],
      ),
      vehicleGuess: $TripsTable.$convertervehicleGuessn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}vehicle_guess'],
        ),
      ),
    );
  }

  @override
  $TripsTable createAlias(String alias) {
    return $TripsTable(attachedDatabase, alias);
  }

  static TypeConverter<DestinationKind, String> $converterdestinationKind =
      const DestinationKindConverter();
  static TypeConverter<DestinationSource, String> $converterdestSource =
      const DestinationSourceConverter();
  static TypeConverter<AlarmModeMsg, String> $convertermode =
      const AlarmModeConverter();
  static TypeConverter<VehicleKindMsg, String> $convertervehicleHint =
      const VehicleKindConverter();
  static TypeConverter<TripOutcomeMsg, String> $converterresult =
      const TripOutcomeConverter();
  static TypeConverter<TripOutcomeMsg?, String?> $converterresultn =
      NullAwareTypeConverter.wrap($converterresult);
  static TypeConverter<EndReasonMsg, String> $converterendReason =
      const EndReasonConverter();
  static TypeConverter<EndReasonMsg?, String?> $converterendReasonn =
      NullAwareTypeConverter.wrap($converterendReason);
  static TypeConverter<AlarmReasonMsg, String> $converteralarmReason =
      const AlarmReasonConverter();
  static TypeConverter<AlarmReasonMsg?, String?> $converteralarmReasonn =
      NullAwareTypeConverter.wrap($converteralarmReason);
  static TypeConverter<VehicleKindMsg, String> $convertervehicleGuess =
      const VehicleKindConverter();
  static TypeConverter<VehicleKindMsg?, String?> $convertervehicleGuessn =
      NullAwareTypeConverter.wrap($convertervehicleGuess);
}

class TripRow extends DataClass implements Insertable<TripRow> {
  /// tripId sent in TripConfigMsg.
  final String id;
  final String destinationName;

  /// Province or address line, display only.
  final String? destinationDetail;
  final DestinationKind destinationKind;
  final double destLat;
  final double destLng;
  final DestinationSource destSource;
  final AlarmModeMsg mode;
  final int? distanceThresholdM;
  final int? timeThresholdMin;
  final bool preAlertEnabled;
  final VehicleKindMsg vehicleHint;
  final bool simulated;
  final int startedAt;
  final int? endedAt;
  final TripOutcomeMsg? result;
  final EndReasonMsg? endReason;
  final int? alarmAt;
  final AlarmReasonMsg? alarmReason;
  final int? dismissedAt;
  final int snoozeCount;
  final int? travelledM;
  final VehicleKindMsg? vehicleGuess;
  const TripRow({
    required this.id,
    required this.destinationName,
    this.destinationDetail,
    required this.destinationKind,
    required this.destLat,
    required this.destLng,
    required this.destSource,
    required this.mode,
    this.distanceThresholdM,
    this.timeThresholdMin,
    required this.preAlertEnabled,
    required this.vehicleHint,
    required this.simulated,
    required this.startedAt,
    this.endedAt,
    this.result,
    this.endReason,
    this.alarmAt,
    this.alarmReason,
    this.dismissedAt,
    required this.snoozeCount,
    this.travelledM,
    this.vehicleGuess,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['destination_name'] = Variable<String>(destinationName);
    if (!nullToAbsent || destinationDetail != null) {
      map['destination_detail'] = Variable<String>(destinationDetail);
    }
    {
      map['destination_kind'] = Variable<String>(
        $TripsTable.$converterdestinationKind.toSql(destinationKind),
      );
    }
    map['dest_lat'] = Variable<double>(destLat);
    map['dest_lng'] = Variable<double>(destLng);
    {
      map['dest_source'] = Variable<String>(
        $TripsTable.$converterdestSource.toSql(destSource),
      );
    }
    {
      map['mode'] = Variable<String>($TripsTable.$convertermode.toSql(mode));
    }
    if (!nullToAbsent || distanceThresholdM != null) {
      map['distance_threshold_m'] = Variable<int>(distanceThresholdM);
    }
    if (!nullToAbsent || timeThresholdMin != null) {
      map['time_threshold_min'] = Variable<int>(timeThresholdMin);
    }
    map['pre_alert_enabled'] = Variable<bool>(preAlertEnabled);
    {
      map['vehicle_hint'] = Variable<String>(
        $TripsTable.$convertervehicleHint.toSql(vehicleHint),
      );
    }
    map['simulated'] = Variable<bool>(simulated);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    if (!nullToAbsent || result != null) {
      map['result'] = Variable<String>(
        $TripsTable.$converterresultn.toSql(result),
      );
    }
    if (!nullToAbsent || endReason != null) {
      map['end_reason'] = Variable<String>(
        $TripsTable.$converterendReasonn.toSql(endReason),
      );
    }
    if (!nullToAbsent || alarmAt != null) {
      map['alarm_at'] = Variable<int>(alarmAt);
    }
    if (!nullToAbsent || alarmReason != null) {
      map['alarm_reason'] = Variable<String>(
        $TripsTable.$converteralarmReasonn.toSql(alarmReason),
      );
    }
    if (!nullToAbsent || dismissedAt != null) {
      map['dismissed_at'] = Variable<int>(dismissedAt);
    }
    map['snooze_count'] = Variable<int>(snoozeCount);
    if (!nullToAbsent || travelledM != null) {
      map['travelled_m'] = Variable<int>(travelledM);
    }
    if (!nullToAbsent || vehicleGuess != null) {
      map['vehicle_guess'] = Variable<String>(
        $TripsTable.$convertervehicleGuessn.toSql(vehicleGuess),
      );
    }
    return map;
  }

  TripsCompanion toCompanion(bool nullToAbsent) {
    return TripsCompanion(
      id: Value(id),
      destinationName: Value(destinationName),
      destinationDetail: destinationDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationDetail),
      destinationKind: Value(destinationKind),
      destLat: Value(destLat),
      destLng: Value(destLng),
      destSource: Value(destSource),
      mode: Value(mode),
      distanceThresholdM: distanceThresholdM == null && nullToAbsent
          ? const Value.absent()
          : Value(distanceThresholdM),
      timeThresholdMin: timeThresholdMin == null && nullToAbsent
          ? const Value.absent()
          : Value(timeThresholdMin),
      preAlertEnabled: Value(preAlertEnabled),
      vehicleHint: Value(vehicleHint),
      simulated: Value(simulated),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      result: result == null && nullToAbsent
          ? const Value.absent()
          : Value(result),
      endReason: endReason == null && nullToAbsent
          ? const Value.absent()
          : Value(endReason),
      alarmAt: alarmAt == null && nullToAbsent
          ? const Value.absent()
          : Value(alarmAt),
      alarmReason: alarmReason == null && nullToAbsent
          ? const Value.absent()
          : Value(alarmReason),
      dismissedAt: dismissedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dismissedAt),
      snoozeCount: Value(snoozeCount),
      travelledM: travelledM == null && nullToAbsent
          ? const Value.absent()
          : Value(travelledM),
      vehicleGuess: vehicleGuess == null && nullToAbsent
          ? const Value.absent()
          : Value(vehicleGuess),
    );
  }

  factory TripRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TripRow(
      id: serializer.fromJson<String>(json['id']),
      destinationName: serializer.fromJson<String>(json['destinationName']),
      destinationDetail: serializer.fromJson<String?>(
        json['destinationDetail'],
      ),
      destinationKind: serializer.fromJson<DestinationKind>(
        json['destinationKind'],
      ),
      destLat: serializer.fromJson<double>(json['destLat']),
      destLng: serializer.fromJson<double>(json['destLng']),
      destSource: serializer.fromJson<DestinationSource>(json['destSource']),
      mode: serializer.fromJson<AlarmModeMsg>(json['mode']),
      distanceThresholdM: serializer.fromJson<int?>(json['distanceThresholdM']),
      timeThresholdMin: serializer.fromJson<int?>(json['timeThresholdMin']),
      preAlertEnabled: serializer.fromJson<bool>(json['preAlertEnabled']),
      vehicleHint: serializer.fromJson<VehicleKindMsg>(json['vehicleHint']),
      simulated: serializer.fromJson<bool>(json['simulated']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int?>(json['endedAt']),
      result: serializer.fromJson<TripOutcomeMsg?>(json['result']),
      endReason: serializer.fromJson<EndReasonMsg?>(json['endReason']),
      alarmAt: serializer.fromJson<int?>(json['alarmAt']),
      alarmReason: serializer.fromJson<AlarmReasonMsg?>(json['alarmReason']),
      dismissedAt: serializer.fromJson<int?>(json['dismissedAt']),
      snoozeCount: serializer.fromJson<int>(json['snoozeCount']),
      travelledM: serializer.fromJson<int?>(json['travelledM']),
      vehicleGuess: serializer.fromJson<VehicleKindMsg?>(json['vehicleGuess']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'destinationName': serializer.toJson<String>(destinationName),
      'destinationDetail': serializer.toJson<String?>(destinationDetail),
      'destinationKind': serializer.toJson<DestinationKind>(destinationKind),
      'destLat': serializer.toJson<double>(destLat),
      'destLng': serializer.toJson<double>(destLng),
      'destSource': serializer.toJson<DestinationSource>(destSource),
      'mode': serializer.toJson<AlarmModeMsg>(mode),
      'distanceThresholdM': serializer.toJson<int?>(distanceThresholdM),
      'timeThresholdMin': serializer.toJson<int?>(timeThresholdMin),
      'preAlertEnabled': serializer.toJson<bool>(preAlertEnabled),
      'vehicleHint': serializer.toJson<VehicleKindMsg>(vehicleHint),
      'simulated': serializer.toJson<bool>(simulated),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int?>(endedAt),
      'result': serializer.toJson<TripOutcomeMsg?>(result),
      'endReason': serializer.toJson<EndReasonMsg?>(endReason),
      'alarmAt': serializer.toJson<int?>(alarmAt),
      'alarmReason': serializer.toJson<AlarmReasonMsg?>(alarmReason),
      'dismissedAt': serializer.toJson<int?>(dismissedAt),
      'snoozeCount': serializer.toJson<int>(snoozeCount),
      'travelledM': serializer.toJson<int?>(travelledM),
      'vehicleGuess': serializer.toJson<VehicleKindMsg?>(vehicleGuess),
    };
  }

  TripRow copyWith({
    String? id,
    String? destinationName,
    Value<String?> destinationDetail = const Value.absent(),
    DestinationKind? destinationKind,
    double? destLat,
    double? destLng,
    DestinationSource? destSource,
    AlarmModeMsg? mode,
    Value<int?> distanceThresholdM = const Value.absent(),
    Value<int?> timeThresholdMin = const Value.absent(),
    bool? preAlertEnabled,
    VehicleKindMsg? vehicleHint,
    bool? simulated,
    int? startedAt,
    Value<int?> endedAt = const Value.absent(),
    Value<TripOutcomeMsg?> result = const Value.absent(),
    Value<EndReasonMsg?> endReason = const Value.absent(),
    Value<int?> alarmAt = const Value.absent(),
    Value<AlarmReasonMsg?> alarmReason = const Value.absent(),
    Value<int?> dismissedAt = const Value.absent(),
    int? snoozeCount,
    Value<int?> travelledM = const Value.absent(),
    Value<VehicleKindMsg?> vehicleGuess = const Value.absent(),
  }) => TripRow(
    id: id ?? this.id,
    destinationName: destinationName ?? this.destinationName,
    destinationDetail: destinationDetail.present
        ? destinationDetail.value
        : this.destinationDetail,
    destinationKind: destinationKind ?? this.destinationKind,
    destLat: destLat ?? this.destLat,
    destLng: destLng ?? this.destLng,
    destSource: destSource ?? this.destSource,
    mode: mode ?? this.mode,
    distanceThresholdM: distanceThresholdM.present
        ? distanceThresholdM.value
        : this.distanceThresholdM,
    timeThresholdMin: timeThresholdMin.present
        ? timeThresholdMin.value
        : this.timeThresholdMin,
    preAlertEnabled: preAlertEnabled ?? this.preAlertEnabled,
    vehicleHint: vehicleHint ?? this.vehicleHint,
    simulated: simulated ?? this.simulated,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    result: result.present ? result.value : this.result,
    endReason: endReason.present ? endReason.value : this.endReason,
    alarmAt: alarmAt.present ? alarmAt.value : this.alarmAt,
    alarmReason: alarmReason.present ? alarmReason.value : this.alarmReason,
    dismissedAt: dismissedAt.present ? dismissedAt.value : this.dismissedAt,
    snoozeCount: snoozeCount ?? this.snoozeCount,
    travelledM: travelledM.present ? travelledM.value : this.travelledM,
    vehicleGuess: vehicleGuess.present ? vehicleGuess.value : this.vehicleGuess,
  );
  TripRow copyWithCompanion(TripsCompanion data) {
    return TripRow(
      id: data.id.present ? data.id.value : this.id,
      destinationName: data.destinationName.present
          ? data.destinationName.value
          : this.destinationName,
      destinationDetail: data.destinationDetail.present
          ? data.destinationDetail.value
          : this.destinationDetail,
      destinationKind: data.destinationKind.present
          ? data.destinationKind.value
          : this.destinationKind,
      destLat: data.destLat.present ? data.destLat.value : this.destLat,
      destLng: data.destLng.present ? data.destLng.value : this.destLng,
      destSource: data.destSource.present
          ? data.destSource.value
          : this.destSource,
      mode: data.mode.present ? data.mode.value : this.mode,
      distanceThresholdM: data.distanceThresholdM.present
          ? data.distanceThresholdM.value
          : this.distanceThresholdM,
      timeThresholdMin: data.timeThresholdMin.present
          ? data.timeThresholdMin.value
          : this.timeThresholdMin,
      preAlertEnabled: data.preAlertEnabled.present
          ? data.preAlertEnabled.value
          : this.preAlertEnabled,
      vehicleHint: data.vehicleHint.present
          ? data.vehicleHint.value
          : this.vehicleHint,
      simulated: data.simulated.present ? data.simulated.value : this.simulated,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      result: data.result.present ? data.result.value : this.result,
      endReason: data.endReason.present ? data.endReason.value : this.endReason,
      alarmAt: data.alarmAt.present ? data.alarmAt.value : this.alarmAt,
      alarmReason: data.alarmReason.present
          ? data.alarmReason.value
          : this.alarmReason,
      dismissedAt: data.dismissedAt.present
          ? data.dismissedAt.value
          : this.dismissedAt,
      snoozeCount: data.snoozeCount.present
          ? data.snoozeCount.value
          : this.snoozeCount,
      travelledM: data.travelledM.present
          ? data.travelledM.value
          : this.travelledM,
      vehicleGuess: data.vehicleGuess.present
          ? data.vehicleGuess.value
          : this.vehicleGuess,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TripRow(')
          ..write('id: $id, ')
          ..write('destinationName: $destinationName, ')
          ..write('destinationDetail: $destinationDetail, ')
          ..write('destinationKind: $destinationKind, ')
          ..write('destLat: $destLat, ')
          ..write('destLng: $destLng, ')
          ..write('destSource: $destSource, ')
          ..write('mode: $mode, ')
          ..write('distanceThresholdM: $distanceThresholdM, ')
          ..write('timeThresholdMin: $timeThresholdMin, ')
          ..write('preAlertEnabled: $preAlertEnabled, ')
          ..write('vehicleHint: $vehicleHint, ')
          ..write('simulated: $simulated, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('result: $result, ')
          ..write('endReason: $endReason, ')
          ..write('alarmAt: $alarmAt, ')
          ..write('alarmReason: $alarmReason, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('snoozeCount: $snoozeCount, ')
          ..write('travelledM: $travelledM, ')
          ..write('vehicleGuess: $vehicleGuess')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    destinationName,
    destinationDetail,
    destinationKind,
    destLat,
    destLng,
    destSource,
    mode,
    distanceThresholdM,
    timeThresholdMin,
    preAlertEnabled,
    vehicleHint,
    simulated,
    startedAt,
    endedAt,
    result,
    endReason,
    alarmAt,
    alarmReason,
    dismissedAt,
    snoozeCount,
    travelledM,
    vehicleGuess,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TripRow &&
          other.id == this.id &&
          other.destinationName == this.destinationName &&
          other.destinationDetail == this.destinationDetail &&
          other.destinationKind == this.destinationKind &&
          other.destLat == this.destLat &&
          other.destLng == this.destLng &&
          other.destSource == this.destSource &&
          other.mode == this.mode &&
          other.distanceThresholdM == this.distanceThresholdM &&
          other.timeThresholdMin == this.timeThresholdMin &&
          other.preAlertEnabled == this.preAlertEnabled &&
          other.vehicleHint == this.vehicleHint &&
          other.simulated == this.simulated &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.result == this.result &&
          other.endReason == this.endReason &&
          other.alarmAt == this.alarmAt &&
          other.alarmReason == this.alarmReason &&
          other.dismissedAt == this.dismissedAt &&
          other.snoozeCount == this.snoozeCount &&
          other.travelledM == this.travelledM &&
          other.vehicleGuess == this.vehicleGuess);
}

class TripsCompanion extends UpdateCompanion<TripRow> {
  final Value<String> id;
  final Value<String> destinationName;
  final Value<String?> destinationDetail;
  final Value<DestinationKind> destinationKind;
  final Value<double> destLat;
  final Value<double> destLng;
  final Value<DestinationSource> destSource;
  final Value<AlarmModeMsg> mode;
  final Value<int?> distanceThresholdM;
  final Value<int?> timeThresholdMin;
  final Value<bool> preAlertEnabled;
  final Value<VehicleKindMsg> vehicleHint;
  final Value<bool> simulated;
  final Value<int> startedAt;
  final Value<int?> endedAt;
  final Value<TripOutcomeMsg?> result;
  final Value<EndReasonMsg?> endReason;
  final Value<int?> alarmAt;
  final Value<AlarmReasonMsg?> alarmReason;
  final Value<int?> dismissedAt;
  final Value<int> snoozeCount;
  final Value<int?> travelledM;
  final Value<VehicleKindMsg?> vehicleGuess;
  final Value<int> rowid;
  const TripsCompanion({
    this.id = const Value.absent(),
    this.destinationName = const Value.absent(),
    this.destinationDetail = const Value.absent(),
    this.destinationKind = const Value.absent(),
    this.destLat = const Value.absent(),
    this.destLng = const Value.absent(),
    this.destSource = const Value.absent(),
    this.mode = const Value.absent(),
    this.distanceThresholdM = const Value.absent(),
    this.timeThresholdMin = const Value.absent(),
    this.preAlertEnabled = const Value.absent(),
    this.vehicleHint = const Value.absent(),
    this.simulated = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.result = const Value.absent(),
    this.endReason = const Value.absent(),
    this.alarmAt = const Value.absent(),
    this.alarmReason = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.snoozeCount = const Value.absent(),
    this.travelledM = const Value.absent(),
    this.vehicleGuess = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TripsCompanion.insert({
    required String id,
    required String destinationName,
    this.destinationDetail = const Value.absent(),
    required DestinationKind destinationKind,
    required double destLat,
    required double destLng,
    required DestinationSource destSource,
    required AlarmModeMsg mode,
    this.distanceThresholdM = const Value.absent(),
    this.timeThresholdMin = const Value.absent(),
    required bool preAlertEnabled,
    required VehicleKindMsg vehicleHint,
    this.simulated = const Value.absent(),
    required int startedAt,
    this.endedAt = const Value.absent(),
    this.result = const Value.absent(),
    this.endReason = const Value.absent(),
    this.alarmAt = const Value.absent(),
    this.alarmReason = const Value.absent(),
    this.dismissedAt = const Value.absent(),
    this.snoozeCount = const Value.absent(),
    this.travelledM = const Value.absent(),
    this.vehicleGuess = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       destinationName = Value(destinationName),
       destinationKind = Value(destinationKind),
       destLat = Value(destLat),
       destLng = Value(destLng),
       destSource = Value(destSource),
       mode = Value(mode),
       preAlertEnabled = Value(preAlertEnabled),
       vehicleHint = Value(vehicleHint),
       startedAt = Value(startedAt);
  static Insertable<TripRow> custom({
    Expression<String>? id,
    Expression<String>? destinationName,
    Expression<String>? destinationDetail,
    Expression<String>? destinationKind,
    Expression<double>? destLat,
    Expression<double>? destLng,
    Expression<String>? destSource,
    Expression<String>? mode,
    Expression<int>? distanceThresholdM,
    Expression<int>? timeThresholdMin,
    Expression<bool>? preAlertEnabled,
    Expression<String>? vehicleHint,
    Expression<bool>? simulated,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<String>? result,
    Expression<String>? endReason,
    Expression<int>? alarmAt,
    Expression<String>? alarmReason,
    Expression<int>? dismissedAt,
    Expression<int>? snoozeCount,
    Expression<int>? travelledM,
    Expression<String>? vehicleGuess,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (destinationName != null) 'destination_name': destinationName,
      if (destinationDetail != null) 'destination_detail': destinationDetail,
      if (destinationKind != null) 'destination_kind': destinationKind,
      if (destLat != null) 'dest_lat': destLat,
      if (destLng != null) 'dest_lng': destLng,
      if (destSource != null) 'dest_source': destSource,
      if (mode != null) 'mode': mode,
      if (distanceThresholdM != null)
        'distance_threshold_m': distanceThresholdM,
      if (timeThresholdMin != null) 'time_threshold_min': timeThresholdMin,
      if (preAlertEnabled != null) 'pre_alert_enabled': preAlertEnabled,
      if (vehicleHint != null) 'vehicle_hint': vehicleHint,
      if (simulated != null) 'simulated': simulated,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (result != null) 'result': result,
      if (endReason != null) 'end_reason': endReason,
      if (alarmAt != null) 'alarm_at': alarmAt,
      if (alarmReason != null) 'alarm_reason': alarmReason,
      if (dismissedAt != null) 'dismissed_at': dismissedAt,
      if (snoozeCount != null) 'snooze_count': snoozeCount,
      if (travelledM != null) 'travelled_m': travelledM,
      if (vehicleGuess != null) 'vehicle_guess': vehicleGuess,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TripsCompanion copyWith({
    Value<String>? id,
    Value<String>? destinationName,
    Value<String?>? destinationDetail,
    Value<DestinationKind>? destinationKind,
    Value<double>? destLat,
    Value<double>? destLng,
    Value<DestinationSource>? destSource,
    Value<AlarmModeMsg>? mode,
    Value<int?>? distanceThresholdM,
    Value<int?>? timeThresholdMin,
    Value<bool>? preAlertEnabled,
    Value<VehicleKindMsg>? vehicleHint,
    Value<bool>? simulated,
    Value<int>? startedAt,
    Value<int?>? endedAt,
    Value<TripOutcomeMsg?>? result,
    Value<EndReasonMsg?>? endReason,
    Value<int?>? alarmAt,
    Value<AlarmReasonMsg?>? alarmReason,
    Value<int?>? dismissedAt,
    Value<int>? snoozeCount,
    Value<int?>? travelledM,
    Value<VehicleKindMsg?>? vehicleGuess,
    Value<int>? rowid,
  }) {
    return TripsCompanion(
      id: id ?? this.id,
      destinationName: destinationName ?? this.destinationName,
      destinationDetail: destinationDetail ?? this.destinationDetail,
      destinationKind: destinationKind ?? this.destinationKind,
      destLat: destLat ?? this.destLat,
      destLng: destLng ?? this.destLng,
      destSource: destSource ?? this.destSource,
      mode: mode ?? this.mode,
      distanceThresholdM: distanceThresholdM ?? this.distanceThresholdM,
      timeThresholdMin: timeThresholdMin ?? this.timeThresholdMin,
      preAlertEnabled: preAlertEnabled ?? this.preAlertEnabled,
      vehicleHint: vehicleHint ?? this.vehicleHint,
      simulated: simulated ?? this.simulated,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      result: result ?? this.result,
      endReason: endReason ?? this.endReason,
      alarmAt: alarmAt ?? this.alarmAt,
      alarmReason: alarmReason ?? this.alarmReason,
      dismissedAt: dismissedAt ?? this.dismissedAt,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      travelledM: travelledM ?? this.travelledM,
      vehicleGuess: vehicleGuess ?? this.vehicleGuess,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (destinationName.present) {
      map['destination_name'] = Variable<String>(destinationName.value);
    }
    if (destinationDetail.present) {
      map['destination_detail'] = Variable<String>(destinationDetail.value);
    }
    if (destinationKind.present) {
      map['destination_kind'] = Variable<String>(
        $TripsTable.$converterdestinationKind.toSql(destinationKind.value),
      );
    }
    if (destLat.present) {
      map['dest_lat'] = Variable<double>(destLat.value);
    }
    if (destLng.present) {
      map['dest_lng'] = Variable<double>(destLng.value);
    }
    if (destSource.present) {
      map['dest_source'] = Variable<String>(
        $TripsTable.$converterdestSource.toSql(destSource.value),
      );
    }
    if (mode.present) {
      map['mode'] = Variable<String>(
        $TripsTable.$convertermode.toSql(mode.value),
      );
    }
    if (distanceThresholdM.present) {
      map['distance_threshold_m'] = Variable<int>(distanceThresholdM.value);
    }
    if (timeThresholdMin.present) {
      map['time_threshold_min'] = Variable<int>(timeThresholdMin.value);
    }
    if (preAlertEnabled.present) {
      map['pre_alert_enabled'] = Variable<bool>(preAlertEnabled.value);
    }
    if (vehicleHint.present) {
      map['vehicle_hint'] = Variable<String>(
        $TripsTable.$convertervehicleHint.toSql(vehicleHint.value),
      );
    }
    if (simulated.present) {
      map['simulated'] = Variable<bool>(simulated.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (result.present) {
      map['result'] = Variable<String>(
        $TripsTable.$converterresultn.toSql(result.value),
      );
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(
        $TripsTable.$converterendReasonn.toSql(endReason.value),
      );
    }
    if (alarmAt.present) {
      map['alarm_at'] = Variable<int>(alarmAt.value);
    }
    if (alarmReason.present) {
      map['alarm_reason'] = Variable<String>(
        $TripsTable.$converteralarmReasonn.toSql(alarmReason.value),
      );
    }
    if (dismissedAt.present) {
      map['dismissed_at'] = Variable<int>(dismissedAt.value);
    }
    if (snoozeCount.present) {
      map['snooze_count'] = Variable<int>(snoozeCount.value);
    }
    if (travelledM.present) {
      map['travelled_m'] = Variable<int>(travelledM.value);
    }
    if (vehicleGuess.present) {
      map['vehicle_guess'] = Variable<String>(
        $TripsTable.$convertervehicleGuessn.toSql(vehicleGuess.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TripsCompanion(')
          ..write('id: $id, ')
          ..write('destinationName: $destinationName, ')
          ..write('destinationDetail: $destinationDetail, ')
          ..write('destinationKind: $destinationKind, ')
          ..write('destLat: $destLat, ')
          ..write('destLng: $destLng, ')
          ..write('destSource: $destSource, ')
          ..write('mode: $mode, ')
          ..write('distanceThresholdM: $distanceThresholdM, ')
          ..write('timeThresholdMin: $timeThresholdMin, ')
          ..write('preAlertEnabled: $preAlertEnabled, ')
          ..write('vehicleHint: $vehicleHint, ')
          ..write('simulated: $simulated, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('result: $result, ')
          ..write('endReason: $endReason, ')
          ..write('alarmAt: $alarmAt, ')
          ..write('alarmReason: $alarmReason, ')
          ..write('dismissedAt: $dismissedAt, ')
          ..write('snoozeCount: $snoozeCount, ')
          ..write('travelledM: $travelledM, ')
          ..write('vehicleGuess: $vehicleGuess, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedPlacesTable extends SavedPlaces
    with TableInfo<$SavedPlacesTable, SavedPlaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedPlacesTable(this.attachedDatabase, [this._alias]);
  @override
  late final GeneratedColumnWithTypeConverter<SavedPlaceSlot, String> slot =
      GeneratedColumn<String>(
        'slot',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SavedPlaceSlot>($SavedPlacesTable.$converterslot);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<DestinationKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<DestinationKind>($SavedPlacesTable.$converterkind);
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    slot,
    name,
    detail,
    kind,
    lat,
    lng,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_places';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedPlaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {slot};
  @override
  SavedPlaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedPlaceRow(
      slot: $SavedPlacesTable.$converterslot.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}slot'],
        )!,
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      kind: $SavedPlacesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SavedPlacesTable createAlias(String alias) {
    return $SavedPlacesTable(attachedDatabase, alias);
  }

  static TypeConverter<SavedPlaceSlot, String> $converterslot =
      const SavedPlaceSlotConverter();
  static TypeConverter<DestinationKind, String> $converterkind =
      const DestinationKindConverter();
}

class SavedPlaceRow extends DataClass implements Insertable<SavedPlaceRow> {
  /// home | hometown | work.
  final SavedPlaceSlot slot;
  final String name;
  final String? detail;
  final DestinationKind kind;
  final double lat;
  final double lng;
  final int updatedAt;
  const SavedPlaceRow({
    required this.slot,
    required this.name,
    this.detail,
    required this.kind,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    {
      map['slot'] = Variable<String>(
        $SavedPlacesTable.$converterslot.toSql(slot),
      );
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    {
      map['kind'] = Variable<String>(
        $SavedPlacesTable.$converterkind.toSql(kind),
      );
    }
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SavedPlacesCompanion toCompanion(bool nullToAbsent) {
    return SavedPlacesCompanion(
      slot: Value(slot),
      name: Value(name),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      kind: Value(kind),
      lat: Value(lat),
      lng: Value(lng),
      updatedAt: Value(updatedAt),
    );
  }

  factory SavedPlaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedPlaceRow(
      slot: serializer.fromJson<SavedPlaceSlot>(json['slot']),
      name: serializer.fromJson<String>(json['name']),
      detail: serializer.fromJson<String?>(json['detail']),
      kind: serializer.fromJson<DestinationKind>(json['kind']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'slot': serializer.toJson<SavedPlaceSlot>(slot),
      'name': serializer.toJson<String>(name),
      'detail': serializer.toJson<String?>(detail),
      'kind': serializer.toJson<DestinationKind>(kind),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SavedPlaceRow copyWith({
    SavedPlaceSlot? slot,
    String? name,
    Value<String?> detail = const Value.absent(),
    DestinationKind? kind,
    double? lat,
    double? lng,
    int? updatedAt,
  }) => SavedPlaceRow(
    slot: slot ?? this.slot,
    name: name ?? this.name,
    detail: detail.present ? detail.value : this.detail,
    kind: kind ?? this.kind,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SavedPlaceRow copyWithCompanion(SavedPlacesCompanion data) {
    return SavedPlaceRow(
      slot: data.slot.present ? data.slot.value : this.slot,
      name: data.name.present ? data.name.value : this.name,
      detail: data.detail.present ? data.detail.value : this.detail,
      kind: data.kind.present ? data.kind.value : this.kind,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlaceRow(')
          ..write('slot: $slot, ')
          ..write('name: $name, ')
          ..write('detail: $detail, ')
          ..write('kind: $kind, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(slot, name, detail, kind, lat, lng, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedPlaceRow &&
          other.slot == this.slot &&
          other.name == this.name &&
          other.detail == this.detail &&
          other.kind == this.kind &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.updatedAt == this.updatedAt);
}

class SavedPlacesCompanion extends UpdateCompanion<SavedPlaceRow> {
  final Value<SavedPlaceSlot> slot;
  final Value<String> name;
  final Value<String?> detail;
  final Value<DestinationKind> kind;
  final Value<double> lat;
  final Value<double> lng;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SavedPlacesCompanion({
    this.slot = const Value.absent(),
    this.name = const Value.absent(),
    this.detail = const Value.absent(),
    this.kind = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedPlacesCompanion.insert({
    required SavedPlaceSlot slot,
    required String name,
    this.detail = const Value.absent(),
    required DestinationKind kind,
    required double lat,
    required double lng,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : slot = Value(slot),
       name = Value(name),
       kind = Value(kind),
       lat = Value(lat),
       lng = Value(lng),
       updatedAt = Value(updatedAt);
  static Insertable<SavedPlaceRow> custom({
    Expression<String>? slot,
    Expression<String>? name,
    Expression<String>? detail,
    Expression<String>? kind,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (slot != null) 'slot': slot,
      if (name != null) 'name': name,
      if (detail != null) 'detail': detail,
      if (kind != null) 'kind': kind,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedPlacesCompanion copyWith({
    Value<SavedPlaceSlot>? slot,
    Value<String>? name,
    Value<String?>? detail,
    Value<DestinationKind>? kind,
    Value<double>? lat,
    Value<double>? lng,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SavedPlacesCompanion(
      slot: slot ?? this.slot,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      kind: kind ?? this.kind,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (slot.present) {
      map['slot'] = Variable<String>(
        $SavedPlacesTable.$converterslot.toSql(slot.value),
      );
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $SavedPlacesTable.$converterkind.toSql(kind.value),
      );
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedPlacesCompanion(')
          ..write('slot: $slot, ')
          ..write('name: $name, ')
          ..write('detail: $detail, ')
          ..write('kind: $kind, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TripsTable trips = $TripsTable(this);
  late final $SavedPlacesTable savedPlaces = $SavedPlacesTable(this);
  late final Index tripsStartedAt = Index(
    'trips_started_at',
    'CREATE INDEX trips_started_at ON trips (started_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    trips,
    savedPlaces,
    tripsStartedAt,
  ];
}

typedef $$TripsTableCreateCompanionBuilder = TripsCompanion Function({
  required String id,
  required String destinationName,
  Value<String?> destinationDetail,
  required DestinationKind destinationKind,
  required double destLat,
  required double destLng,
  required DestinationSource destSource,
  required AlarmModeMsg mode,
  Value<int?> distanceThresholdM,
  Value<int?> timeThresholdMin,
  required bool preAlertEnabled,
  required VehicleKindMsg vehicleHint,
  Value<bool> simulated,
  required int startedAt,
  Value<int?> endedAt,
  Value<TripOutcomeMsg?> result,
  Value<EndReasonMsg?> endReason,
  Value<int?> alarmAt,
  Value<AlarmReasonMsg?> alarmReason,
  Value<int?> dismissedAt,
  Value<int> snoozeCount,
  Value<int?> travelledM,
  Value<VehicleKindMsg?> vehicleGuess,
  Value<int> rowid,
});
typedef $$TripsTableUpdateCompanionBuilder = TripsCompanion Function({
  Value<String> id,
  Value<String> destinationName,
  Value<String?> destinationDetail,
  Value<DestinationKind> destinationKind,
  Value<double> destLat,
  Value<double> destLng,
  Value<DestinationSource> destSource,
  Value<AlarmModeMsg> mode,
  Value<int?> distanceThresholdM,
  Value<int?> timeThresholdMin,
  Value<bool> preAlertEnabled,
  Value<VehicleKindMsg> vehicleHint,
  Value<bool> simulated,
  Value<int> startedAt,
  Value<int?> endedAt,
  Value<TripOutcomeMsg?> result,
  Value<EndReasonMsg?> endReason,
  Value<int?> alarmAt,
  Value<AlarmReasonMsg?> alarmReason,
  Value<int?> dismissedAt,
  Value<int> snoozeCount,
  Value<int?> travelledM,
  Value<VehicleKindMsg?> vehicleGuess,
  Value<int> rowid,
});

class $$TripsTableFilterComposer extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationName => $composableBuilder(
    column: $table.destinationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationDetail => $composableBuilder(
    column: $table.destinationDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DestinationKind, DestinationKind, String>
  get destinationKind => $composableBuilder(
    column: $table.destinationKind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<double> get destLat => $composableBuilder(
    column: $table.destLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get destLng => $composableBuilder(
    column: $table.destLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DestinationSource, DestinationSource, String>
  get destSource => $composableBuilder(
    column: $table.destSource,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<AlarmModeMsg, AlarmModeMsg, String> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get distanceThresholdM => $composableBuilder(
    column: $table.distanceThresholdM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeThresholdMin => $composableBuilder(
    column: $table.timeThresholdMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get preAlertEnabled => $composableBuilder(
    column: $table.preAlertEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<VehicleKindMsg, VehicleKindMsg, String>
  get vehicleHint => $composableBuilder(
    column: $table.vehicleHint,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get simulated => $composableBuilder(
    column: $table.simulated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TripOutcomeMsg?, TripOutcomeMsg, String>
  get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<EndReasonMsg?, EndReasonMsg, String>
  get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get alarmAt => $composableBuilder(
    column: $table.alarmAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AlarmReasonMsg?, AlarmReasonMsg, String>
  get alarmReason => $composableBuilder(
    column: $table.alarmReason,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get travelledM => $composableBuilder(
    column: $table.travelledM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<VehicleKindMsg?, VehicleKindMsg, String>
  get vehicleGuess => $composableBuilder(
    column: $table.vehicleGuess,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$TripsTableOrderingComposer
    extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationName => $composableBuilder(
    column: $table.destinationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationDetail => $composableBuilder(
    column: $table.destinationDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationKind => $composableBuilder(
    column: $table.destinationKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get destLat => $composableBuilder(
    column: $table.destLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get destLng => $composableBuilder(
    column: $table.destLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destSource => $composableBuilder(
    column: $table.destSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distanceThresholdM => $composableBuilder(
    column: $table.distanceThresholdM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeThresholdMin => $composableBuilder(
    column: $table.timeThresholdMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get preAlertEnabled => $composableBuilder(
    column: $table.preAlertEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleHint => $composableBuilder(
    column: $table.vehicleHint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get simulated => $composableBuilder(
    column: $table.simulated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get result => $composableBuilder(
    column: $table.result,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get alarmAt => $composableBuilder(
    column: $table.alarmAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alarmReason => $composableBuilder(
    column: $table.alarmReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get travelledM => $composableBuilder(
    column: $table.travelledM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vehicleGuess => $composableBuilder(
    column: $table.vehicleGuess,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TripsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TripsTable> {
  $$TripsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get destinationName => $composableBuilder(
    column: $table.destinationName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationDetail => $composableBuilder(
    column: $table.destinationDetail,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<DestinationKind, String>
  get destinationKind => $composableBuilder(
    column: $table.destinationKind,
    builder: (column) => column,
  );

  GeneratedColumn<double> get destLat =>
      $composableBuilder(column: $table.destLat, builder: (column) => column);

  GeneratedColumn<double> get destLng =>
      $composableBuilder(column: $table.destLng, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DestinationSource, String> get destSource =>
      $composableBuilder(
        column: $table.destSource,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<AlarmModeMsg, String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get distanceThresholdM => $composableBuilder(
    column: $table.distanceThresholdM,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timeThresholdMin => $composableBuilder(
    column: $table.timeThresholdMin,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get preAlertEnabled => $composableBuilder(
    column: $table.preAlertEnabled,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<VehicleKindMsg, String> get vehicleHint =>
      $composableBuilder(
        column: $table.vehicleHint,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get simulated =>
      $composableBuilder(column: $table.simulated, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TripOutcomeMsg?, String> get result =>
      $composableBuilder(column: $table.result, builder: (column) => column);

  GeneratedColumnWithTypeConverter<EndReasonMsg?, String> get endReason =>
      $composableBuilder(column: $table.endReason, builder: (column) => column);

  GeneratedColumn<int> get alarmAt =>
      $composableBuilder(column: $table.alarmAt, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AlarmReasonMsg?, String> get alarmReason =>
      $composableBuilder(
        column: $table.alarmReason,
        builder: (column) => column,
      );

  GeneratedColumn<int> get dismissedAt => $composableBuilder(
    column: $table.dismissedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snoozeCount => $composableBuilder(
    column: $table.snoozeCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get travelledM => $composableBuilder(
    column: $table.travelledM,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<VehicleKindMsg?, String> get vehicleGuess =>
      $composableBuilder(
        column: $table.vehicleGuess,
        builder: (column) => column,
      );
}

class $$TripsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TripsTable,
          TripRow,
          $$TripsTableFilterComposer,
          $$TripsTableOrderingComposer,
          $$TripsTableAnnotationComposer,
          $$TripsTableCreateCompanionBuilder,
          $$TripsTableUpdateCompanionBuilder,
          (TripRow, BaseReferences<_$AppDatabase, $TripsTable, TripRow>),
          TripRow,
          PrefetchHooks Function()
        > {
  $$TripsTableTableManager(_$AppDatabase db, $TripsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TripsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TripsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TripsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> destinationName = const Value.absent(),
                Value<String?> destinationDetail = const Value.absent(),
                Value<DestinationKind> destinationKind = const Value.absent(),
                Value<double> destLat = const Value.absent(),
                Value<double> destLng = const Value.absent(),
                Value<DestinationSource> destSource = const Value.absent(),
                Value<AlarmModeMsg> mode = const Value.absent(),
                Value<int?> distanceThresholdM = const Value.absent(),
                Value<int?> timeThresholdMin = const Value.absent(),
                Value<bool> preAlertEnabled = const Value.absent(),
                Value<VehicleKindMsg> vehicleHint = const Value.absent(),
                Value<bool> simulated = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<TripOutcomeMsg?> result = const Value.absent(),
                Value<EndReasonMsg?> endReason = const Value.absent(),
                Value<int?> alarmAt = const Value.absent(),
                Value<AlarmReasonMsg?> alarmReason = const Value.absent(),
                Value<int?> dismissedAt = const Value.absent(),
                Value<int> snoozeCount = const Value.absent(),
                Value<int?> travelledM = const Value.absent(),
                Value<VehicleKindMsg?> vehicleGuess = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripsCompanion(
                id: id,
                destinationName: destinationName,
                destinationDetail: destinationDetail,
                destinationKind: destinationKind,
                destLat: destLat,
                destLng: destLng,
                destSource: destSource,
                mode: mode,
                distanceThresholdM: distanceThresholdM,
                timeThresholdMin: timeThresholdMin,
                preAlertEnabled: preAlertEnabled,
                vehicleHint: vehicleHint,
                simulated: simulated,
                startedAt: startedAt,
                endedAt: endedAt,
                result: result,
                endReason: endReason,
                alarmAt: alarmAt,
                alarmReason: alarmReason,
                dismissedAt: dismissedAt,
                snoozeCount: snoozeCount,
                travelledM: travelledM,
                vehicleGuess: vehicleGuess,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String destinationName,
                Value<String?> destinationDetail = const Value.absent(),
                required DestinationKind destinationKind,
                required double destLat,
                required double destLng,
                required DestinationSource destSource,
                required AlarmModeMsg mode,
                Value<int?> distanceThresholdM = const Value.absent(),
                Value<int?> timeThresholdMin = const Value.absent(),
                required bool preAlertEnabled,
                required VehicleKindMsg vehicleHint,
                Value<bool> simulated = const Value.absent(),
                required int startedAt,
                Value<int?> endedAt = const Value.absent(),
                Value<TripOutcomeMsg?> result = const Value.absent(),
                Value<EndReasonMsg?> endReason = const Value.absent(),
                Value<int?> alarmAt = const Value.absent(),
                Value<AlarmReasonMsg?> alarmReason = const Value.absent(),
                Value<int?> dismissedAt = const Value.absent(),
                Value<int> snoozeCount = const Value.absent(),
                Value<int?> travelledM = const Value.absent(),
                Value<VehicleKindMsg?> vehicleGuess = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TripsCompanion.insert(
                id: id,
                destinationName: destinationName,
                destinationDetail: destinationDetail,
                destinationKind: destinationKind,
                destLat: destLat,
                destLng: destLng,
                destSource: destSource,
                mode: mode,
                distanceThresholdM: distanceThresholdM,
                timeThresholdMin: timeThresholdMin,
                preAlertEnabled: preAlertEnabled,
                vehicleHint: vehicleHint,
                simulated: simulated,
                startedAt: startedAt,
                endedAt: endedAt,
                result: result,
                endReason: endReason,
                alarmAt: alarmAt,
                alarmReason: alarmReason,
                dismissedAt: dismissedAt,
                snoozeCount: snoozeCount,
                travelledM: travelledM,
                vehicleGuess: vehicleGuess,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TripsTable, TripRow>(table),
                  BaseReferences<_$AppDatabase, $TripsTable, TripRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TripsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TripsTable,
      TripRow,
      $$TripsTableFilterComposer,
      $$TripsTableOrderingComposer,
      $$TripsTableAnnotationComposer,
      $$TripsTableCreateCompanionBuilder,
      $$TripsTableUpdateCompanionBuilder,
      (TripRow, BaseReferences<_$AppDatabase, $TripsTable, TripRow>),
      TripRow,
      PrefetchHooks Function()
    >;
typedef $$SavedPlacesTableCreateCompanionBuilder =
    SavedPlacesCompanion Function({
      required SavedPlaceSlot slot,
      required String name,
      Value<String?> detail,
      required DestinationKind kind,
      required double lat,
      required double lng,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$SavedPlacesTableUpdateCompanionBuilder =
    SavedPlacesCompanion Function({
      Value<SavedPlaceSlot> slot,
      Value<String> name,
      Value<String?> detail,
      Value<DestinationKind> kind,
      Value<double> lat,
      Value<double> lng,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$SavedPlacesTableFilterComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnWithTypeConverterFilters<SavedPlaceSlot, SavedPlaceSlot, String>
  get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DestinationKind, DestinationKind, String>
  get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedPlacesTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedPlacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedPlacesTable> {
  $$SavedPlacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumnWithTypeConverter<SavedPlaceSlot, String> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DestinationKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SavedPlacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedPlacesTable,
          SavedPlaceRow,
          $$SavedPlacesTableFilterComposer,
          $$SavedPlacesTableOrderingComposer,
          $$SavedPlacesTableAnnotationComposer,
          $$SavedPlacesTableCreateCompanionBuilder,
          $$SavedPlacesTableUpdateCompanionBuilder,
          (
            SavedPlaceRow,
            BaseReferences<_$AppDatabase, $SavedPlacesTable, SavedPlaceRow>,
          ),
          SavedPlaceRow,
          PrefetchHooks Function()
        > {
  $$SavedPlacesTableTableManager(_$AppDatabase db, $SavedPlacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedPlacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedPlacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedPlacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<SavedPlaceSlot> slot = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<DestinationKind> kind = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedPlacesCompanion(
                slot: slot,
                name: name,
                detail: detail,
                kind: kind,
                lat: lat,
                lng: lng,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required SavedPlaceSlot slot,
                required String name,
                Value<String?> detail = const Value.absent(),
                required DestinationKind kind,
                required double lat,
                required double lng,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedPlacesCompanion.insert(
                slot: slot,
                name: name,
                detail: detail,
                kind: kind,
                lat: lat,
                lng: lng,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedPlacesTable, SavedPlaceRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SavedPlacesTable,
                    SavedPlaceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedPlacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedPlacesTable,
      SavedPlaceRow,
      $$SavedPlacesTableFilterComposer,
      $$SavedPlacesTableOrderingComposer,
      $$SavedPlacesTableAnnotationComposer,
      $$SavedPlacesTableCreateCompanionBuilder,
      $$SavedPlacesTableUpdateCompanionBuilder,
      (
        SavedPlaceRow,
        BaseReferences<_$AppDatabase, $SavedPlacesTable, SavedPlaceRow>,
      ),
      SavedPlaceRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TripsTableTableManager get trips =>
      $$TripsTableTableManager(_db, _db.trips);
  $$SavedPlacesTableTableManager get savedPlaces =>
      $$SavedPlacesTableTableManager(_db, _db.savedPlaces);
}

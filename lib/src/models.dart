// Data models mirroring the server's wire contract (snake_case JSON).

const List<String> kModes = ['AUTO', 'COOL', 'DRY', 'HEAT', 'FAN_ONLY'];
const Map<String, String> kModeLabels = {
  'AUTO': 'auto',
  'COOL': 'cool',
  'DRY': 'dry',
  'HEAT': 'heat',
  'FAN_ONLY': 'fan',
};
const List<String> kSwingModes = ['OFF', 'VERTICAL', 'HORIZONTAL', 'BOTH'];

// The fan speeds the UI exposes (server also accepts 40/80).
const List<int> kFanSpeeds = [20, 60, 100, 102];
const Map<int, String> kFanLabels = {20: 'low', 60: 'med', 100: 'high', 102: 'auto'};

const double kMinTemp = 16.0;
const double kMaxTemp = 30.0;

double _toD(Object? v) => (v as num).toDouble();
double? _toDN(Object? v) => v == null ? null : (v as num).toDouble();

class UnitSummary {
  final String id;
  final String name;
  final String ip;
  UnitSummary({required this.id, required this.name, required this.ip});
  factory UnitSummary.fromJson(Map<String, dynamic> j) =>
      UnitSummary(id: j['id'] as String, name: j['name'] as String, ip: j['ip'] as String);
}

class UnitState {
  final String id;
  final String name;
  final String ip;
  final bool online;
  final bool powerState;
  final String operationalMode;
  final double targetTemperature;
  final double? indoorTemperature;
  final double? outdoorTemperature;
  final int fanSpeed;
  final String swingMode;
  final bool eco;
  final bool turbo;

  UnitState({
    required this.id,
    required this.name,
    required this.ip,
    required this.online,
    required this.powerState,
    required this.operationalMode,
    required this.targetTemperature,
    required this.indoorTemperature,
    required this.outdoorTemperature,
    required this.fanSpeed,
    required this.swingMode,
    required this.eco,
    required this.turbo,
  });

  factory UnitState.fromJson(Map<String, dynamic> j) => UnitState(
        id: j['id'] as String,
        name: j['name'] as String,
        ip: j['ip'] as String,
        online: j['online'] as bool,
        powerState: j['power_state'] as bool,
        operationalMode: j['operational_mode'] as String,
        targetTemperature: _toD(j['target_temperature']),
        indoorTemperature: _toDN(j['indoor_temperature']),
        outdoorTemperature: _toDN(j['outdoor_temperature']),
        fanSpeed: (j['fan_speed'] as num).toInt(),
        swingMode: j['swing_mode'] as String,
        eco: j['eco'] as bool,
        turbo: j['turbo'] as bool,
      );
}

/// A partial control payload — only non-null fields are sent/applied.
class ClimateSettings {
  bool? powerState;
  String? operationalMode;
  double? targetTemperature;
  int? fanSpeed;
  String? swingMode;
  bool? eco;
  bool? turbo;

  ClimateSettings({
    this.powerState,
    this.operationalMode,
    this.targetTemperature,
    this.fanSpeed,
    this.swingMode,
    this.eco,
    this.turbo,
  });

  factory ClimateSettings.fromJson(Map<String, dynamic> j) => ClimateSettings(
        powerState: j['power_state'] as bool?,
        operationalMode: j['operational_mode'] as String?,
        targetTemperature: _toDN(j['target_temperature']),
        fanSpeed: (j['fan_speed'] as num?)?.toInt(),
        swingMode: j['swing_mode'] as String?,
        eco: j['eco'] as bool?,
        turbo: j['turbo'] as bool?,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (powerState != null) m['power_state'] = powerState;
    if (operationalMode != null) m['operational_mode'] = operationalMode;
    if (targetTemperature != null) m['target_temperature'] = targetTemperature;
    if (fanSpeed != null) m['fan_speed'] = fanSpeed;
    if (swingMode != null) m['swing_mode'] = swingMode;
    if (eco != null) m['eco'] = eco;
    if (turbo != null) m['turbo'] = turbo;
    return m;
  }

  ClimateSettings copy() => ClimateSettings.fromJson(toJson());
}

class ScheduleEntry {
  List<int> days; // 0=Mon..6=Sun, empty=every day
  String time; // "HH:MM"
  ClimateSettings settings;
  ScheduleEntry({required this.days, required this.time, required this.settings});

  factory ScheduleEntry.fromJson(Map<String, dynamic> j) => ScheduleEntry(
        days: (j['days'] as List).map((e) => e as int).toList(),
        time: j['time'] as String,
        settings: ClimateSettings.fromJson(j['settings'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() =>
      {'days': days, 'time': time, 'settings': settings.toJson()};
}

class CurvePoint {
  String time; // "HH:MM"
  double temperature;
  CurvePoint({required this.time, required this.temperature});

  factory CurvePoint.fromJson(Map<String, dynamic> j) =>
      CurvePoint(time: j['time'] as String, temperature: _toD(j['temperature']));

  Map<String, dynamic> toJson() => {'time': time, 'temperature': temperature};
}

class CurveConfig {
  String operationalMode;
  int fanSpeed;
  List<CurvePoint> points;
  CurveConfig({
    this.operationalMode = 'COOL',
    this.fanSpeed = 102,
    required this.points,
  });

  factory CurveConfig.fromJson(Map<String, dynamic> j) => CurveConfig(
        operationalMode: j['operational_mode'] as String,
        fanSpeed: (j['fan_speed'] as num).toInt(),
        points: (j['points'] as List)
            .map((e) => CurvePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'operational_mode': operationalMode,
        'fan_speed': fanSpeed,
        'points': points.map((p) => p.toJson()).toList(),
      };
}

class Program {
  String id;
  String name;
  bool enabled;
  List<String> unitIds; // empty = all units
  String kind; // favourite | schedule | curve
  ClimateSettings? favourite;
  List<ScheduleEntry> schedule;
  CurveConfig? curve;

  Program({
    required this.id,
    required this.name,
    required this.enabled,
    required this.unitIds,
    required this.kind,
    this.favourite,
    required this.schedule,
    this.curve,
  });

  factory Program.fromJson(Map<String, dynamic> j) => Program(
        id: j['id'] as String,
        name: j['name'] as String,
        enabled: j['enabled'] as bool,
        unitIds: (j['unit_ids'] as List).map((e) => e as String).toList(),
        kind: j['kind'] as String,
        favourite: j['favourite'] == null
            ? null
            : ClimateSettings.fromJson(j['favourite'] as Map<String, dynamic>),
        schedule: (j['schedule'] as List? ?? [])
            .map((e) => ScheduleEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        curve: j['curve'] == null
            ? null
            : CurveConfig.fromJson(j['curve'] as Map<String, dynamic>),
      );

  /// Body for POST/PUT (server assigns the id).
  Map<String, dynamic> toSpecJson() {
    final m = <String, dynamic>{
      'name': name,
      'enabled': enabled,
      'unit_ids': unitIds,
      'kind': kind,
      'schedule': schedule.map((e) => e.toJson()).toList(),
    };
    if (favourite != null) m['favourite'] = favourite!.toJson();
    if (curve != null) m['curve'] = curve!.toJson();
    return m;
  }
}

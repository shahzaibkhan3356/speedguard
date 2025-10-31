import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpeedState {
  final bool isMeasuring;
  final double filteredSpeed;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool useMph;
  final double speedLimit;
  final bool overSpeed;
  final bool isMoving;
  final bool gpsAvailable;
  final double gpsAccuracy;
  final int gpsStrength;
  final bool isLinearMotion;
  final int confidenceLevel;

  const SpeedState({
    required this.isMeasuring,
    required this.filteredSpeed,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.useMph,
    required this.speedLimit,
    required this.overSpeed,
    required this.isMoving,
    required this.gpsAvailable,
    required this.gpsAccuracy,
    required this.gpsStrength,
    required this.isLinearMotion,
    required this.confidenceLevel,
  });

  factory SpeedState.initial() => const SpeedState(
    isMeasuring: false,
    filteredSpeed: 0.0,
    soundEnabled: true,
    vibrationEnabled: true,
    useMph: false,
    speedLimit: 60.0,
    overSpeed: false,
    isMoving: false,
    gpsAvailable: false,
    gpsAccuracy: 0.0,
    gpsStrength: 0,
    isLinearMotion: false,
    confidenceLevel: 0,
  );

  SpeedState copyWith({
    bool? isMeasuring,
    double? filteredSpeed,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? useMph,
    double? speedLimit,
    bool? overSpeed,
    bool? isMoving,
    bool? gpsAvailable,
    double? gpsAccuracy,
    int? gpsStrength,
    bool? isLinearMotion,
    int? confidenceLevel,
  }) {
    return SpeedState(
      isMeasuring: isMeasuring ?? this.isMeasuring,
      filteredSpeed: filteredSpeed ?? this.filteredSpeed,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      useMph: useMph ?? this.useMph,
      speedLimit: speedLimit ?? this.speedLimit,
      overSpeed: overSpeed ?? this.overSpeed,
      isMoving: isMoving ?? this.isMoving,
      gpsAvailable: gpsAvailable ?? this.gpsAvailable,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      gpsStrength: gpsStrength ?? this.gpsStrength,
      isLinearMotion: isLinearMotion ?? this.isLinearMotion,
      confidenceLevel: confidenceLevel ?? this.confidenceLevel,
    );
  }
}

class SpeedCubit extends Cubit<SpeedState> {
  double _estimate = 0.0;
  double _errorCov = 1.0;
  double _predictedSpeed = 0.0;
  DateTime _lastUpdate = DateTime.now();

  final List<double> _accelHistory = [];
  final List<double> _gyroHistory = [];
  static const int _motionWindow = 10;

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  Timer? _motionTimer;
  bool _motionDetected = false;
  int _motionConfidence = 0; // 0–100 confidence
  double _lastStableSpeed = 0.0;
  @override
  Future<void> close() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _motionTimer?.cancel();
    return super.close();
  }

  SpeedCubit() : super(SpeedState.initial()) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    emit(
      state.copyWith(
        soundEnabled: prefs.getBool('soundEnabled') ?? true,
        vibrationEnabled: prefs.getBool('vibrationEnabled') ?? true,
        useMph: prefs.getBool('useMph') ?? false,
        speedLimit: prefs.getDouble('speedLimit') ?? 60.0,
      ),
    );
  }

  // ====== START / STOP ======
  Future<void> start() async {
    emit(state.copyWith(isMeasuring: true));
    _startGps();
    _startSensors();
    _startMotionTimer();
  }

  Future<void> stop() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _motionTimer?.cancel();
    emit(state.copyWith(isMeasuring: false, filteredSpeed: 0.0));
  }

  // ====== GPS ======
  void _startGps() {
    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen((pos) {
          final gpsSpeed = (pos.speed.isNaN || pos.speed.isInfinite)
              ? 0.0
              : pos.speed * 3.6;
          final gpsAcc = pos.accuracy;
          final gpsStrength = _gpsStrength(gpsAcc);

          _processFusion(gpsSpeed, gpsAcc, gpsStrength);
        });
  }

  // ====== SENSOR INPUT ======
  void _startSensors() {
    _accelSub = userAccelerometerEventStream().listen((a) {
      final mag = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
      _accelHistory.add(mag.abs());
      if (_accelHistory.length > _motionWindow) _accelHistory.removeAt(0);
    });

    _gyroSub = gyroscopeEventStream().listen((g) {
      final mag = math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
      _gyroHistory.add(mag.abs());
      if (_gyroHistory.length > _motionWindow) _gyroHistory.removeAt(0);
    });
  }

  void _startMotionTimer() {
    _motionTimer?.cancel();
    int noMotionCount = 0;

    _motionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final motion = _isLinearMotion();

      if (motion) {
        _motionConfidence = (_motionConfidence + 8).clamp(0, 100);
        noMotionCount = 0;
      } else {
        _motionConfidence = (_motionConfidence - 12).clamp(0, 100);
        noMotionCount++;
      }

      _motionDetected = _motionConfidence > 40;

      // If no motion for 1.5s (6 cycles), lock to 0 instantly
      if (noMotionCount >= 6 && _estimate < 4.0) {
        _predictedSpeed = 0.0;
        _estimate = 0.0;
        emit(state.copyWith(filteredSpeed: 0.0, isMoving: false));
      }
    });
  }

  // ====== FUSION ======
  void _processFusion(double gpsSpeed, double gpsAcc, int gpsStrength) {
    final now = DateTime.now();
    final dt = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    _lastUpdate = now;

    final linearAccel = _accelHistory.isEmpty
        ? 0.0
        : (_accelHistory.last - 9.81).clamp(-4.0, 4.0);
    _predictedSpeed = (_predictedSpeed + linearAccel * 3.6 * dt).clamp(0, 400);

    // Noise filter: ignore spikes if no motion or large jump
    final speedDiff = (gpsSpeed - _estimate).abs();
    if (!_motionDetected && gpsSpeed < 2.0) {
      _estimate = 0.0;
      _lastStableSpeed = 0.0;
      return;
    }
    if (speedDiff > 40 && !_motionDetected) return; // likely GPS glitch
    // If very low motion and speed < 1.5 km/h, force zero
    if (!_motionDetected && _estimate < 1.5) {
      _estimate = 0.0;
    }

    // Adaptive weighting by GPS quality & motion confidence
    double motionFactor = (_motionConfidence / 100).clamp(0.2, 1.0);
    final wGps = (gpsStrength / 100.0) * motionFactor;
    final wSensor = 1 - wGps;
    final fused = gpsSpeed * wGps + _predictedSpeed * wSensor;

    _updateKalman(fused, gpsAcc);

    final moving = _estimate > 1.5;
    final over = _estimate > state.speedLimit;
    final isLinear = _motionDetected;

    _lastStableSpeed = _estimate;

    emit(
      state.copyWith(
        filteredSpeed: _estimate,
        gpsAccuracy: gpsAcc,
        gpsStrength: gpsStrength,
        gpsAvailable: true,
        isLinearMotion: isLinear,
        isMoving: moving,
        overSpeed: over,
        confidenceLevel: _calcConfidence(gpsStrength, isLinear),
      ),
    );
  }

  // ====== KALMAN ======
  void _updateKalman(double meas, double gpsAcc) {
    final R = _adaptiveR(gpsAcc);
    final Q = gpsAcc > 15 ? 0.3 : 0.1;
    _errorCov += Q;
    final K = _errorCov / (_errorCov + R);
    _estimate += K * (meas - _estimate);
    _errorCov *= (1 - K);
    _estimate = _estimate.clamp(0, 400);
  }

  double _adaptiveR(double acc) {
    if (acc < 5) return 0.3;
    if (acc < 10) return 1.5;
    if (acc < 20) return 3;
    if (acc < 40) return 5;
    return 8;
  }

  int _gpsStrength(double acc) {
    if (acc <= 5) return 100;
    if (acc <= 10) return 90;
    if (acc <= 15) return 75;
    if (acc <= 25) return 50;
    if (acc <= 50) return 25;
    return 10;
  }

  bool _isLinearMotion() {
    final accelAvg = _accelHistory.isEmpty
        ? 0
        : _accelHistory.reduce((a, b) => a + b) / _accelHistory.length;
    final gyroAvg = _gyroHistory.isEmpty
        ? 0
        : _gyroHistory.reduce((a, b) => a + b) / _gyroHistory.length;

    // Increased thresholds for stronger motion detection
    const accelThreshold = 0.55; // was 0.12
    const gyroThreshold = 0.35; // was 0.1
    return accelAvg > accelThreshold || gyroAvg > gyroThreshold;
  }

  int _calcConfidence(int gpsStrength, bool isLinear) {
    int conf = gpsStrength;
    if (!isLinear) conf = (conf * 0.5).toInt();
    return conf.clamp(0, 100);
  }

  // ====== SETTINGS ======
  Future<void> toggleSound() async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !state.soundEnabled;
    await prefs.setBool('soundEnabled', newVal);
    emit(state.copyWith(soundEnabled: newVal));
  }

  Future<void> toggleVibration() async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !state.vibrationEnabled;
    await prefs.setBool('vibrationEnabled', newVal);
    emit(state.copyWith(vibrationEnabled: newVal));
  }

  Future<void> toggleUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final newUnit = !state.useMph;
    final newLimit = newUnit
        ? _kmhToMph(state.speedLimit)
        : _mphToKmh(state.speedLimit);
    await prefs.setBool('useMph', newUnit);
    await prefs.setDouble('speedLimit', newLimit);
    emit(state.copyWith(useMph: newUnit, speedLimit: newLimit));
  }

  Future<void> updateSpeedLimit(double newLimit) async {
    final prefs = await SharedPreferences.getInstance();
    final limitKmh = state.useMph ? _mphToKmh(newLimit) : newLimit;
    await prefs.setDouble('speedLimit', limitKmh);
    emit(state.copyWith(speedLimit: limitKmh));
  }

  double _kmhToMph(double kmh) => kmh * 0.621371;
  double _mphToKmh(double mph) => mph / 0.621371;
}

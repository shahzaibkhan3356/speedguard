import 'dart:async';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// ---------- EVENTS ----------
@immutable
abstract class SpeedEvent {}

class StartMeasurement extends SpeedEvent {}

class StopMeasurement extends SpeedEvent {}

class LoadPreferences extends SpeedEvent {}

class ToggleSound extends SpeedEvent {}

class ToggleVibration extends SpeedEvent {}

class ToggleSpeedUnit extends SpeedEvent {}

class UpdateSpeedLimit extends SpeedEvent {
  final double speedLimit;
  UpdateSpeedLimit(this.speedLimit);
}

/// ---------- STATE ----------
@immutable
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

/// ---------- BLOC ----------
class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  // --- Core variables ---
  double _estimate = 0.0;
  double _errorCov = 1.0;
  double _integratedSpeed = 0.0;
  DateTime? _lastAccelTime;
  double _lastAccel = 9.81;
  double _lastGyro = 0.0;

  // --- Streams ---
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // --- Alerts ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _alertTimer;
  bool _alertActive = false;

  SpeedBloc()
    : super(
        const SpeedState(
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
        ),
      ) {
    on<LoadPreferences>(_onLoadPrefs);
    on<StartMeasurement>(_onStart);
    on<StopMeasurement>(_onStop);
    on<ToggleSound>(_onToggleSound);
    on<ToggleVibration>(_onToggleVibration);
    on<ToggleSpeedUnit>(_onToggleUnit);
    on<UpdateSpeedLimit>(_onUpdateLimit);

    add(LoadPreferences());
  }

  @override
  Future<void> close() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _alertTimer?.cancel();
    await _audioPlayer.dispose();
    return super.close();
  }

  // ---------- Preferences ----------
  Future<void> _onLoadPrefs(LoadPreferences e, Emitter<SpeedState> emit) async {
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

  // ---------- Start ----------
  void _onStart(StartMeasurement e, Emitter<SpeedState> emit) async {
    emit(state.copyWith(isMeasuring: true));

    _startGps();
    _startSensors();

    debugPrint('[SpeedBloc] Measurement started');
  }

  // ---------- Stop ----------
  void _onStop(StopMeasurement e, Emitter<SpeedState> emit) async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _stopAlert();
    emit(state.copyWith(isMeasuring: false));
    debugPrint('[SpeedBloc] Measurement stopped');
  }

  // ---------- GPS Stream ----------
  void _startGps() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      debugPrint('[GPS] Permission denied forever.');
      return;
    }

    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          ),
        ).listen((pos) {
          final gpsSpeed = (pos.speed.isNaN || pos.speed.isInfinite)
              ? 0.0
              : pos.speed * 3.6;

          final gpsAcc = pos.accuracy;
          final gpsStr = _gpsStrength(gpsAcc);

          _processFusion(gpsSpeed, gpsAcc, gpsStr);
        }, onError: (e) => debugPrint('[GPS] Error: $e'));
  }

  // ---------- Sensor Streams ----------
  void _startSensors() {
    _accelSub = userAccelerometerEventStream().listen((a) {
      _lastAccel = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
      _integrateImuSpeed();
    });

    _gyroSub = gyroscopeEventStream().listen((g) {
      _lastGyro = math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
    });
  }

  // ---------- Sensor Integration ----------
  void _integrateImuSpeed() {
    final now = DateTime.now();
    final dt = _lastAccelTime == null
        ? 0.1
        : now.difference(_lastAccelTime!).inMilliseconds / 1000.0;
    _lastAccelTime = now;

    final linAccel = (_lastAccel - 9.81).clamp(-3, 3);
    _integratedSpeed += linAccel * 3.6 * dt;
    _integratedSpeed = _integratedSpeed.clamp(0, 300);
  }

  // ---------- Adaptive Fusion ----------
  void _processFusion(double gpsSpeed, double gpsAcc, int gpsStrength) {
    final isLinear = _isLinearMotion(_lastAccel, _lastGyro);
    final fusedSpeed = _fuseSpeeds(gpsSpeed, _integratedSpeed, gpsStrength);
    _updateKalman(fusedSpeed, gpsAcc);

    final moving = _estimate > 1.5;
    final over = _estimate > state.speedLimit;

    _handleAlert(over, moving);

    emit(
      state.copyWith(
        filteredSpeed: _estimate,
        gpsAccuracy: gpsAcc,
        gpsAvailable: true,
        gpsStrength: gpsStrength,
        isLinearMotion: isLinear,
        isMoving: moving,
        overSpeed: over,
        confidenceLevel: _calcConfidence(gpsStrength, isLinear),
      ),
    );

    // 🔍 Debug output
    debugPrint(
      '[GPS] Speed: ${gpsSpeed.toStringAsFixed(2)} km/h, '
      'Acc: ${gpsAcc.toStringAsFixed(1)}m, '
      'Strength: $gpsStrength%, '
      'Fused: ${_estimate.toStringAsFixed(2)} km/h',
    );
  }

  // ---------- Fusion Logic ----------
  double _fuseSpeeds(double gps, double imu, int strength) {
    double wGps, wImu;
    if (strength >= 80) {
      wGps = 1.0;
      wImu = 0.0;
    } else if (strength >= 50) {
      wGps = 0.6;
      wImu = 0.4;
    } else if (strength >= 20) {
      wGps = 0.3;
      wImu = 0.7;
    } else {
      wGps = 0.0;
      wImu = 1.0;
    }
    return gps * wGps + imu * wImu;
  }

  void _updateKalman(double meas, double gpsAcc) {
    final R = _adaptiveR(gpsAcc);
    final Q = gpsAcc > 15 ? 0.3 : 0.1;
    _errorCov += Q;
    final K = _errorCov / (_errorCov + R);
    _estimate += K * (meas - _estimate);
    _errorCov *= (1 - K);
    _estimate = _estimate.clamp(0, 300);
  }

  // ---------- Utils ----------
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
    return 0;
  }

  bool _isLinearMotion(double accel, double gyro) =>
      (accel - 9.81).abs() > 0.15 && gyro < 0.3;

  int _calcConfidence(int gpsStrength, bool isLinear) {
    int conf = gpsStrength;
    if (!isLinear) conf = (conf * 0.5).toInt();
    return conf.clamp(0, 100);
  }

  Future<void> _handleAlert(bool over, bool moving) async {
    // Instant, frame-by-frame check instead of periodic timer
    if (over && moving) {
      if (!_alertActive) {
        _alertActive = true;

        // Respect toggles every frame
        if (state.soundEnabled) await _startSound();
        if (state.vibrationEnabled) await _startVibration();

        _showAlertSnackbar();
      }
    } else if (_alertActive) {
      await _stopAlert();
    }
  }

  void _showAlertSnackbar() {
    // Close any older snackbar to avoid stacking
    Get.closeAllSnackbars();
    Get.snackbar(
      "Speed Limit 🚨",
      "You're over the limit! ${_estimate.toStringAsFixed(1)} km/h",
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.withOpacity(0.9),
      colorText: Colors.white,
      duration: const Duration(seconds: 1),
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
    );
  }

  Future<void> _startSound() async {
    try {
      await _audioPlayer.setAsset("assets/alert-33762.mp3");
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.play();
    } catch (_) {}
  }

  Future<void> _startVibration() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 600, 300], repeat: 1);
    }
  }

  Future<void> _stopAlert() async {
    _alertActive = false;
    await _stopSound();
    await _stopVibration();
  }

  Future<void> _stopSound() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> _stopVibration() async {
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.cancel();
      }
    } catch (_) {}
  }

  Future<void> _onToggleSound(ToggleSound e, Emitter<SpeedState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !state.soundEnabled;
    await prefs.setBool('soundEnabled', newValue);
    emit(state.copyWith(soundEnabled: newValue));

    // If sound was just disabled, stop it now
    if (!newValue) await _stopSound();
  }

  Future<void> _onToggleVibration(
    ToggleVibration e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final newValue = !state.vibrationEnabled;
    await prefs.setBool('vibrationEnabled', newValue);
    emit(state.copyWith(vibrationEnabled: newValue));

    // If vibration was just disabled, stop it now
    if (!newValue) await _stopVibration();
  }

  Future<void> _onToggleUnit(
    ToggleSpeedUnit e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final newUnit = !state.useMph;
    final newLimit = newUnit
        ? _kmhToMph(state.speedLimit)
        : _mphToKmh(state.speedLimit);
    prefs.setBool('useMph', newUnit);
    prefs.setDouble('speedLimit', newLimit);
    emit(state.copyWith(useMph: newUnit, speedLimit: newLimit));
  }

  Future<void> _onUpdateLimit(
    UpdateSpeedLimit e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final limitKmh = state.useMph ? _mphToKmh(e.speedLimit) : e.speedLimit;
    prefs.setDouble('speedLimit', limitKmh);
    emit(state.copyWith(speedLimit: limitKmh));
  }

  double _kmhToMph(double kmh) => kmh * 0.621371;
  double _mphToKmh(double mph) => mph / 0.621371;
}

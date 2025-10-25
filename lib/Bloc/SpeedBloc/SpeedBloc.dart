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

// Internal events for decoupling streams
class _PredictSpeed extends SpeedEvent {}

class _CorrectSpeed extends SpeedEvent {
  final double gpsSpeed;
  final double gpsAcc;
  _CorrectSpeed(this.gpsSpeed, this.gpsAcc);
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
  // Core filters (Kalman)
  double _estimate = 0.0;
  double _errorCov = 1.0; // P_k-1: Initial uncertainty
  double _predictedSpeed = 0.0;
  DateTime _lastUpdate = DateTime.now();
  final double _motionThreshold =
      0.2; // m/s² threshold for detecting absolute motion

  // Sensors / Subscriptions
  final AccelerometerEvent _lastAccel = AccelerometerEvent(
    0,
    0,
    0,
    DateTime.now(),
  );
  GyroscopeEvent _lastGyro = GyroscopeEvent(0, 0, 0, DateTime.now());
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Alerts
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _alertActive = false;

  // Last GPS measurement used for Correction step
  double _lastGpsSpeed = 0.0;
  double _lastGpsAcc = 999.0;
  int _lastGpsStrength = 0;

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

    // Internal handlers for the decoupled streams
    on<_PredictSpeed>(_onPredictSpeed); // Driven by IMU stream
    on<_CorrectSpeed>(_onCorrectSpeed); // Driven by GPS stream

    add(LoadPreferences());
  }

  // ---------- Lifecycle ----------
  @override
  Future<void> close() async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _audioPlayer.dispose();
    return super.close();
  }

  // ---------- Start/Stop Handlers ----------
  void _onStart(StartMeasurement e, Emitter<SpeedState> emit) async {
    emit(state.copyWith(isMeasuring: true));
    _startGps();
    _startSensors();
    debugPrint('[SpeedBloc] Started measurement');
  }

  void _onStop(StopMeasurement e, Emitter<SpeedState> emit) async {
    await _gpsSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _stopAlert();
    // Reset filters on stop
    _estimate = 0.0;
    _errorCov = 1.0;
    _predictedSpeed = 0.0;
    emit(
      state.copyWith(isMeasuring: false, filteredSpeed: 0.0, isMoving: false),
    );
    debugPrint('[SpeedBloc] Stopped measurement');
  }

  // ---------- GPS (Correction) ----------
  void _startGps() {
    // 1. GPS setup
    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0, // Receive all updates
          ),
        ).listen((pos) {
          final gpsSpeed = (pos.speed.isNaN || pos.speed.isInfinite)
              ? 0.0
              : pos.speed * 3.6; // m/s to km/h

          // Dispatch the correction event
          add(_CorrectSpeed(gpsSpeed, pos.accuracy));
        });
  }

  // ---------- Sensors (Prediction) ----------
  void _startSensors() {
    // 1. Subscribe to Accel (high-frequency) to drive the prediction loop
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((e) => add(_PredictSpeed()));

    // 2. Subscribe to Gyro for stillness check and motion classification
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((e) => _lastGyro = e);
  }

  // ---------- Core Motion Logic ----------

  /// Uses IMU to strictly check if the device is stationary.
  bool get _isAbsolutelyStill {
    final accelMag = math.sqrt(
      _lastAccel.x * _lastAccel.x +
          _lastAccel.y * _lastAccel.y +
          _lastAccel.z * _lastAccel.z,
    );
    final gyroMag = math.sqrt(
      _lastGyro.x * _lastGyro.x +
          _lastGyro.y * _lastGyro.y +
          _lastGyro.z * _lastGyro.z,
    );

    // Check if linear motion (accel - gravity) and rotation are minimal
    return (accelMag - 9.81).abs() < _motionThreshold && gyroMag < 0.1;
  }

  // ----------------------------------------------------
  // 🚀 Prediction Handler (IMU-Driven - FAST)
  // ----------------------------------------------------
  void _onPredictSpeed(_PredictSpeed e, Emitter<SpeedState> emit) {
    if (!state.isMeasuring) return;

    final now = DateTime.now();
    final dt = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    _lastUpdate = now;

    // 1. STRICT ZERO-SPEED LOCK: Override if the IMU detects no motion.
    if (_isAbsolutelyStill) {
      _estimate = 0.0;
      _predictedSpeed = 0.0;
      _errorCov = 1.0; // Reset P to max uncertainty for fast startup
    } else {
      // 2. Dead Reckoning (Prediction)
      // Estimate change in speed using linear acceleration
      final accelMag = math.sqrt(
        _lastAccel.x * _lastAccel.x +
            _lastAccel.y * _lastAccel.y +
            _lastAccel.z * _lastAccel.z,
      );
      final linearAccel = (accelMag - 9.81).clamp(-4.0, 4.0); // Remove gravity
      _predictedSpeed = (_predictedSpeed + linearAccel * 3.6 * dt).clamp(
        0,
        400,
      );

      // 3. Adaptive Q Boost for Responsiveness
      final qBoost =
          linearAccel.abs() * 0.2; // Increase Q if accelerating/decelerating

      // 4. Update Filter using IMU prediction (Prediction Step Only)
      // Use a high R to reduce trust in the IMU speed alone.
      _updateKalman(_predictedSpeed, _lastGpsAcc, Q_boost: qBoost);
    }

    // 5. State Update (for smooth UI rendering)
    final moving = _estimate > 1.5;
    final over = _estimate > state.speedLimit;

    // Recalculate isLinearMotion using the latest data
    final accelMagForLinear = math.sqrt(
      _lastAccel.x * _lastAccel.x +
          _lastAccel.y * _lastAccel.y +
          _lastAccel.z * _lastAccel.z,
    );
    final isLinear = _isLinearMotion(accelMagForLinear, _lastGyro);

    _handleAlert(over, moving);

    emit(
      state.copyWith(
        filteredSpeed: _estimate,
        isLinearMotion: isLinear,
        isMoving: moving,
        overSpeed: over,
        // GPS related states only updated in _onCorrectSpeed
        confidenceLevel: _calcConfidence(_lastGpsStrength, isLinear),
      ),
    );
  }

  // ----------------------------------------------------
  // 🧭 Correction Handler (GPS-Driven - SLOW)
  // ----------------------------------------------------
  void _onCorrectSpeed(_CorrectSpeed e, Emitter<SpeedState> emit) {
    if (!state.isMeasuring || _isAbsolutelyStill) return;

    // 1. Store last GPS data
    _lastGpsSpeed = e.gpsSpeed;
    _lastGpsAcc = e.gpsAcc;
    _lastGpsStrength = _gpsStrength(e.gpsAcc);

    // 2. Correction Step: Update filter using the GPS measurement
    // Q_boost is zero here as the prediction step already handled it.
    _updateKalman(_lastGpsSpeed, _lastGpsAcc, Q_boost: 0.0);

    // 3. State Update for GPS status
    emit(
      state.copyWith(
        gpsAvailable: true,
        gpsAccuracy: _lastGpsAcc,
        gpsStrength: _lastGpsStrength,
      ),
    );

    debugPrint(
      "[Correction] GPS:${_lastGpsSpeed.toStringAsFixed(2)} "
      "Fused:${_estimate.toStringAsFixed(2)} "
      "Acc:${_lastGpsAcc.toStringAsFixed(1)}m "
      "Str:$_lastGpsStrength%",
    );
  }

  // ---------- Kalman Utilities ----------

  void _updateKalman(double meas, double acc, {required double Q_boost}) {
    // 1. Prediction (Process Covariance)
    final qBase = 0.05;
    final Q = qBase + Q_boost;
    _errorCov += Q;

    // 2. Adaptive R (Measurement Noise)
    final R = _adaptiveR(acc);

    // 3. Kalman Gain
    final K = _errorCov / (_errorCov + R);

    // 4. Correction
    _estimate += K * (meas - _estimate);

    // 5. Update Covariance
    _errorCov *= (1 - K);

    _estimate = _estimate.clamp(0, 400);
  }

  double _adaptiveR(double acc) {
    // R (Measurement Noise) is inversely related to GPS accuracy.
    if (acc < 3.0) return 0.2; // High confidence (trust GPS correction a lot)
    if (acc < 6.0) return 0.8;
    if (acc < 10.0) return 3.0;
    if (acc < 20.0) return 8.0;
    return 15.0; // Low confidence (trust IMU prediction more)
  }

  // ---------- Helper Methods (Intact) ----------

  int _gpsStrength(double acc) {
    if (acc <= 5) return 100;
    if (acc <= 10) return 90;
    if (acc <= 15) return 75;
    if (acc <= 25) return 50;
    if (acc <= 50) return 25;
    return 10;
  }

  bool _isLinearMotion(double accelMag, GyroscopeEvent g) {
    final gyroMag = math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
    return (accelMag - 9.81).abs() > 0.15 && gyroMag < 0.3;
  }

  int _calcConfidence(int gpsStrength, bool isLinear) {
    int conf = gpsStrength;
    if (!isLinear) conf = (conf * 0.5).toInt();
    return conf.clamp(0, 100);
  }

  // ---------- Toggles and Settings (Intact) ----------
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

  Future<void> _onToggleSound(ToggleSound e, Emitter<SpeedState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !state.soundEnabled;
    await prefs.setBool('soundEnabled', newVal);
    emit(state.copyWith(soundEnabled: newVal));
    if (!newVal) await _stopSound();
  }

  Future<void> _onToggleVibration(
    ToggleVibration e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !state.vibrationEnabled;
    await prefs.setBool('vibrationEnabled', newVal);
    emit(state.copyWith(vibrationEnabled: newVal));
    if (!newVal) await _stopVibration();
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
    await prefs.setBool('useMph', newUnit);
    await prefs.setDouble('speedLimit', newLimit);
    emit(state.copyWith(useMph: newUnit, speedLimit: newLimit));
  }

  Future<void> _onUpdateLimit(
    UpdateSpeedLimit e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final limitKmh = state.useMph ? _mphToKmh(e.speedLimit) : e.speedLimit;
    await prefs.setDouble('speedLimit', limitKmh);
    emit(state.copyWith(speedLimit: limitKmh));
  }

  double _kmhToMph(double kmh) => kmh * 0.621371;
  double _mphToKmh(double mph) => mph / 0.621371;

  // ---------- Alerts (Intact) ----------
  Future<void> _handleAlert(bool over, bool moving) async {
    if (over && moving) {
      if (!_alertActive) {
        _alertActive = true;
        if (state.soundEnabled) await _startSound();
        if (state.vibrationEnabled) await _startVibration();
        _showAlertSnackbar();
      }
    } else if (_alertActive) {
      await _stopAlert();
    }
  }

  void _showAlertSnackbar() {
    Get.closeAllSnackbars();
    Get.snackbar(
      "Speed Limit 🚨",
      "Over Speed! ${_estimate.toStringAsFixed(1)} km/h",
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red.withOpacity(0.9),
      colorText: Colors.white,
      duration: const Duration(milliseconds: 1500),
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
    if (await Vibration.hasVibrator() ?? false) {
      // Use shorter, repeated pattern for alerts
      Vibration.vibrate(pattern: [0, 300, 100, 300], repeat: 0);
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
      if (await Vibration.hasVibrator() ?? false) Vibration.cancel();
    } catch (_) {}
  }
}

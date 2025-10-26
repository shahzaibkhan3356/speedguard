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

// --- CONSTANTS FOR PROFESSIONAL FILTERING ---
const double _STILL_ACCEL_THRESHOLD =
    0.5; // m/s^2 (Tolerance for linear movement)
const double _STILL_GYRO_THRESHOLD = 0.05; // rad/s (Tolerance for rotation)
const double _EMA_ALPHA = 0.9;

/// ================= EVENTS =================
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

class GpsServiceToggled extends SpeedEvent {
  final bool isEnabled;
  GpsServiceToggled(this.isEnabled);
}

// NEW: Event to carry position data from the stream
class GpsDataReceived extends SpeedEvent {
  final Position position;
  GpsDataReceived(this.position);
}

/// ================= STATE =================
@immutable
class SpeedState {
  final bool isMeasuring;
  final double filteredSpeed;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool useMph;
  final double speedLimit;
  final bool overSpeed;
  final bool gpsAvailable;
  final double gpsAccuracy;
  final int gpsStrength;
  final bool gpsServiceEnabled;

  const SpeedState({
    required this.isMeasuring,
    required this.filteredSpeed,
    required this.soundEnabled,
    required this.vibrationEnabled,
    required this.useMph,
    required this.speedLimit,
    required this.overSpeed,
    required this.gpsAvailable,
    required this.gpsAccuracy,
    required this.gpsStrength,
    required this.gpsServiceEnabled,
  });

  SpeedState copyWith({
    bool? isMeasuring,
    double? filteredSpeed,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? useMph,
    double? speedLimit,
    bool? overSpeed,
    bool? gpsAvailable,
    double? gpsAccuracy,
    int? gpsStrength,
    bool? gpsServiceEnabled,
  }) {
    return SpeedState(
      isMeasuring: isMeasuring ?? this.isMeasuring,
      filteredSpeed: filteredSpeed ?? this.filteredSpeed,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      useMph: useMph ?? this.useMph,
      speedLimit: speedLimit ?? this.speedLimit,
      overSpeed: overSpeed ?? this.overSpeed,
      gpsAvailable: gpsAvailable ?? this.gpsAvailable,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      gpsStrength: gpsStrength ?? this.gpsStrength,
      gpsServiceEnabled: gpsServiceEnabled ?? this.gpsServiceEnabled,
    );
  }
}

/// ================= BLOC =================
class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  // Core variables
  double _filteredSpeed = 0.0;
  double _lastGpsSpeed = 0.0;
  double _lastGpsAcc = 15.0;

  // Sensor variables for Zero-Lock
  double _linearAccelMagnitude = 0.0;
  double _gyroMagnitude = 0.0;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<ServiceStatus>? _gpsServiceSub;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  // Timer for high-frequency state emission (100 ms)
  Timer? _updateTimer;

  // Alerts
  final AudioPlayer _audioPlayer = AudioPlayer();
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
          gpsAvailable: false,
          gpsAccuracy: 0.0,
          gpsStrength: 0,
          gpsServiceEnabled: true,
        ),
      ) {
    on<LoadPreferences>(_onLoadPrefs);
    on<StartMeasurement>(_onStart);
    on<StopMeasurement>(_onStop);
    on<ToggleSound>(_onToggleSound);
    on<ToggleVibration>(_onToggleVibration);
    on<ToggleSpeedUnit>(_onToggleUnit);
    on<UpdateSpeedLimit>(_onUpdateLimit);
    on<GpsServiceToggled>(_onGpsServiceToggled);
    on<GpsDataReceived>(_onGpsDataReceived); // NEW: Handler for GPS data

    add(LoadPreferences());
  }

  @override
  Future<void> close() {
    _gpsSub?.cancel();
    _gpsServiceSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _updateTimer?.cancel();
    _audioPlayer.dispose();
    return super.close();
  }

  // ============ START/STOP ============
  void _onStart(StartMeasurement e, Emitter<SpeedState> emit) async {
    _filteredSpeed = 0.0;
    _lastGpsSpeed = 0.0;

    emit(state.copyWith(isMeasuring: true));

    _startGps(); // Removed 'emit' argument
    _startSensors();
    _startGpsServiceListener();

    final initialStatus = await Geolocator.isLocationServiceEnabled();
    if (!initialStatus) {
      add(GpsServiceToggled(false));
    }

    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      _applyZeroLock();

      emit(
        state.copyWith(
          filteredSpeed: _filteredSpeed,
          overSpeed: _filteredSpeed > state.speedLimit,
        ),
      );
      _handleAlerts();
    });

    debugPrint("[SpeedBloc] Measurement started");
  }

  void _onStop(StopMeasurement e, Emitter<SpeedState> emit) async {
    await _gpsSub?.cancel();
    await _gpsServiceSub?.cancel();
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _updateTimer?.cancel();
    await _stopAlert();

    _filteredSpeed = 0.0;
    _lastGpsSpeed = 0.0;

    emit(state.copyWith(isMeasuring: false, filteredSpeed: 0.0));
    debugPrint("[SpeedBloc] Measurement stopped");
  }

  // ============ GPS LISTENERS & ALERT ============

  void _startGpsServiceListener() {
    _gpsServiceSub = Geolocator.getServiceStatusStream().listen((status) {
      final isEnabled = status == ServiceStatus.enabled;
      add(GpsServiceToggled(isEnabled));
    });
  }

  void _onGpsServiceToggled(GpsServiceToggled e, Emitter<SpeedState> emit) {
    emit(state.copyWith(gpsServiceEnabled: e.isEnabled));

    if (!e.isEnabled) {
      _filteredSpeed = 0.0;
      _lastGpsSpeed = 0.0;
      _stopAlert();

      emit(
        state.copyWith(
          filteredSpeed: 0.0,
          gpsAvailable: false,
          gpsAccuracy: 0.0,
          gpsStrength: 0,
        ),
      );

      Get.snackbar(
        "⚠️ GPS Service Required",
        "Location services are disabled. Please enable GPS to continue measuring speed.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade900,
        colorText: Colors.white,
        isDismissible: false,
        duration: const Duration(minutes: 5),
        mainButton: TextButton(
          onPressed: () {
            Geolocator.openLocationSettings();
          },
          child: const Text(
            'Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else {
      if (Get.isSnackbarOpen) {
        Get.back();
      }
    }
  }

  // FIX: This method no longer calls emit. It adds an event.
  void _startGps() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) return;

    _gpsSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen((pos) {
          // Stream listener now adds an event, which is the correct BLoC pattern.
          add(GpsDataReceived(pos));
        });
  }

  // NEW: Handler to process GPS data and safely emit state
  void _onGpsDataReceived(GpsDataReceived e, Emitter<SpeedState> emit) {
    final pos = e.position;

    // Prevent processing stale data if the service is disabled
    if (!state.gpsServiceEnabled) return;

    final gpsSpeedKmh = pos.speed.isFinite ? pos.speed * 3.6 : 0.0;
    final gpsAcc = pos.accuracy;
    final gpsStr = _gpsStrength(gpsAcc);
    debugPrint(
      "[SpeedBloc] GPS Data - Speed: ${gpsSpeedKmh.toStringAsFixed(2)} km/h, Accuracy: ${gpsAcc.toStringAsFixed(2)} m, Strength: $gpsStr%",
    );
    _lastGpsSpeed = gpsSpeedKmh;
    _lastGpsAcc = gpsAcc;

    _applyExponentialSmoothing(gpsSpeedKmh);

    // This emit is now safely within the synchronous scope of the event handler.
    emit(
      state.copyWith(
        gpsAvailable: true,
        gpsAccuracy: gpsAcc,
        gpsStrength: gpsStr,
      ),
    );
  }

  // ============ SENSOR & FILTERING LOGIC ============
  void _startSensors() {
    _accelSub =
        userAccelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 50),
        ).listen((a) {
          _linearAccelMagnitude = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
        });

    _gyroSub =
        gyroscopeEventStream(
          samplingPeriod: const Duration(milliseconds: 50),
        ).listen((g) {
          _gyroMagnitude = math.sqrt(g.x * g.x + g.y * g.y + g.z * g.z);
        });
  }

  void _applyExponentialSmoothing(double newGpsSpeed) {
    _filteredSpeed =
        (_EMA_ALPHA * newGpsSpeed) + ((1 - _EMA_ALPHA) * _filteredSpeed);
  }

  void _applyZeroLock() {
    final isStill =
        _linearAccelMagnitude < _STILL_ACCEL_THRESHOLD &&
        _gyroMagnitude < _STILL_GYRO_THRESHOLD;

    final gpsIsNearZero = _lastGpsSpeed < 5.0;

    if (isStill && gpsIsNearZero) {
      _filteredSpeed = 0.0;
    }

    _filteredSpeed = _filteredSpeed.clamp(0, 240);
  }

  int _gpsStrength(double acc) {
    if (acc <= 5) return 100;
    if (acc <= 10) return 90;
    if (acc <= 15) return 75;
    if (acc <= 25) return 50;
    if (acc <= 50) return 25;
    return 10;
  }

  // ============ SPEED LIMIT & PREFS / ALERTS ============

  Future<void> _onUpdateLimit(
    UpdateSpeedLimit e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final newLimitKmh = state.useMph ? _mphToKmh(e.speedLimit) : e.speedLimit;

    await prefs.setDouble('speedLimit', newLimitKmh);
    final newOverSpeed = _filteredSpeed > newLimitKmh;

    emit(state.copyWith(speedLimit: newLimitKmh, overSpeed: newOverSpeed));

    _handleAlerts();
  }

  Future<void> _handleAlerts() async {
    final over = _filteredSpeed > state.speedLimit;
    if (over && !_alertActive) {
      _alertActive = true;

      Get.snackbar(
        "Speed Limit 🚨",
        "Over Speed! ${_filteredSpeed.toStringAsFixed(1)} km/h",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );

      if (state.soundEnabled) await _startSound();
      if (state.vibrationEnabled) await _startVibration();
    } else if (!over && _alertActive) {
      await _stopAlert();
    }
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
      Vibration.vibrate(pattern: [0, 500, 300], repeat: 1);
    }
  }

  Future<void> _stopAlert() async {
    _alertActive = false;
    await _audioPlayer.stop();
    if (await Vibration.hasVibrator() ?? false) Vibration.cancel();
  }

  // ============ TOGGLES & UTILITIES (Unchanged) ============
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
    if (!newVal) await _audioPlayer.stop();
  }

  Future<void> _onToggleVibration(
    ToggleVibration e,
    Emitter<SpeedState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final newVal = !state.vibrationEnabled;
    await prefs.setBool('vibrationEnabled', newVal);
    emit(state.copyWith(vibrationEnabled: newVal));
    if (!newVal && await Vibration.hasVibrator() ?? false) Vibration.cancel();
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

  double _kmhToMph(double kmh) => kmh * 0.621371;
  double _mphToKmh(double mph) => mph / 0.621371;
}

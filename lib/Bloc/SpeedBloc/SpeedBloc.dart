import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// EVENTS
abstract class SpeedEvent {}
class StartTracking extends SpeedEvent {}
class StopTracking extends SpeedEvent {}
class _SpeedUpdate extends SpeedEvent {
  final double speedKmh;
  _SpeedUpdate(this.speedKmh);
}

/// STATES
abstract class SpeedState {}
class SpeedInitial extends SpeedState {}
class SpeedLoading extends SpeedState {}
class SpeedUpdated extends SpeedState {
  final double speedKmh;
  SpeedUpdated(this.speedKmh);
}
class SpeedError extends SpeedState {
  final String message;
  SpeedError(this.message);
}

/// --- Simple Kalman Filter ---
class KalmanFilter {
  double _estimate = 0.0;
  double _errorEstimate = 1.0;
  final double _errorMeasure;
  final double _processNoise;

  KalmanFilter({
    double errorMeasure = 1.0,
    double processNoise = 0.01,
  })  : _errorMeasure = errorMeasure,
        _processNoise = processNoise;

  double filter(double measurement) {
    _errorEstimate += _processNoise;
    double kalmanGain = _errorEstimate / (_errorEstimate + _errorMeasure);
    _estimate = _estimate + kalmanGain * (measurement - _estimate);
    _errorEstimate = (1 - kalmanGain) * _errorEstimate;
    return _estimate;
  }

  void reset() {
    _estimate = 0.0;
    _errorEstimate = 1.0;
  }
}

/// --- BLOC ---
class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<AccelerometerEvent>? _accelStream;
  Timer? _fusionTimer;

  final KalmanFilter _kalman = KalmanFilter(errorMeasure: 1.5, processNoise: 0.05);

  double _currentSpeed = 0.0;
  double _accMagnitude = 0.0;
  double _gpsSpeed = 0.0;
  DateTime _lastGpsUpdate = DateTime.now();

  SpeedBloc() : super(SpeedInitial()) {
    on<StartTracking>(_onStartTracking);
    on<StopTracking>(_onStopTracking);
    on<_SpeedUpdate>((event, emit) => emit(SpeedUpdated(event.speedKmh)));
  }

  Future<void> _onStartTracking(StartTracking event, Emitter<SpeedState> emit) async {
    emit(SpeedLoading());
    try {
      // Check GPS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        emit(SpeedError("Location services are disabled."));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          emit(SpeedError("Location permissions are denied."));
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        emit(SpeedError(
            "Location permissions are permanently denied. Enable them in settings."));
        return;
      }

      // --- Accelerometer Stream ---
      _accelStream?.cancel();
      _accelStream = accelerometerEvents.listen((event) {
        // Compute motion magnitude
        final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        final motion = (mag - 9.8).abs(); // remove gravity
        _accMagnitude = motion < 0.15 ? 0.0 : motion; // noise filter
      });

      // --- GPS Stream ---
      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        _gpsSpeed = pos.speed * 3.6; // m/s → km/h
        _lastGpsUpdate = DateTime.now();
      });

      // --- Sensor Fusion ---
      _fusionTimer?.cancel();
      _fusionTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
        if (isClosed) {
          timer.cancel();
          return;
        }

        final gpsStale = DateTime.now().difference(_lastGpsUpdate).inMilliseconds > 3000;

        // If GPS is stale, rely more on accelerometer prediction
        double fusedSpeed;
        if (gpsStale) {
          // Small predicted increase if moving
          fusedSpeed = _currentSpeed + _accMagnitude * 0.4;
        } else {
          // Combine GPS + motion input
          fusedSpeed = (_gpsSpeed * 0.85) + (_accMagnitude * 1.2);
        }

        // Apply Kalman smoothing
        double filtered = _kalman.filter(fusedSpeed);

        // Detect stationary state
        if (filtered < 0.5 && _accMagnitude < 0.2) {
          filtered = 0.0;
          _kalman.reset();
        }

        // Clamp and store
        filtered = filtered.clamp(0.0, 240.0);
        _currentSpeed = filtered;

        if (!isClosed) add(_SpeedUpdate(_currentSpeed));
      });
    } catch (e) {
      emit(SpeedError("Speed tracking error: $e"));
    }
  }

  Future<void> _onStopTracking(StopTracking event, Emitter<SpeedState> emit) async {
    await _positionStream?.cancel();
    await _accelStream?.cancel();
    _fusionTimer?.cancel();
    _currentSpeed = 0.0;
    _accMagnitude = 0.0;
    _gpsSpeed = 0.0;
    _kalman.reset();
    emit(SpeedInitial());
  }

  @override
  Future<void> close() async {
    await _positionStream?.cancel();
    await _accelStream?.cancel();
    _fusionTimer?.cancel();
    return super.close();
  }
}

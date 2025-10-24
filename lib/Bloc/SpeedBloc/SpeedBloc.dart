import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Configuration constants
class SpeedConfig {
  static const Duration fusionUpdateInterval = Duration(milliseconds: 250);
  static const double accelMultiplier = 0.4;
  static const double gpsWeight = 0.85;
  static const double accelWeight = 1.2;
  static const int gpsStaleThresholdMs = 3000;
  static const double stationarySpeedThreshold = 0.5;
  static const double stationaryAccelThreshold = 0.2;
  static const double gravityMagnitude = 9.8;
  static const double accelNoiseFilter = 0.15;
  static const double maxSpeed = 240.0;
}

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

/// Simple Kalman Filter for speed smoothing
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

  /// Apply Kalman filter to measurement
  double filter(double measurement) {
    _errorEstimate += _processNoise;
    double kalmanGain = _errorEstimate / (_errorEstimate + _errorMeasure);
    _estimate = _estimate + kalmanGain * (measurement - _estimate);
    _errorEstimate = (1 - kalmanGain) * _errorEstimate;
    return _estimate;
  }

  /// Reset filter state
  void reset() {
    _estimate = 0.0;
    _errorEstimate = 1.0;
  }
}

/// BLoC for real-time speed tracking using GPS and accelerometer fusion
///
/// Uses a Kalman filter to smooth speed readings and handles GPS dropout
/// gracefully by predicting speed from accelerometer data.
class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<AccelerometerEvent>? _accelStream;
  Timer? _fusionTimer;

  final KalmanFilter _kalman = KalmanFilter(
    errorMeasure: 1.5,
    processNoise: 0.05,
  );

  double _currentSpeed = 0.0;
  double _accMagnitude = 0.0;
  double _gpsSpeed = 0.0;
  DateTime? _lastGpsUpdate; // Nullable to detect initial state

  SpeedBloc() : super(SpeedInitial()) {
    on<StartTracking>(_onStartTracking);
    on<StopTracking>(_onStopTracking);
    on<_SpeedUpdate>((event, emit) => emit(SpeedUpdated(event.speedKmh)));
  }

  Future<void> _onStartTracking(
      StartTracking event, Emitter<SpeedState> emit) async {
    // Clean up any existing streams first
    await _cleanup();

    emit(SpeedLoading());

    try {
      // Check GPS service
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        emit(SpeedError("Location services are disabled."));
        return;
      }

      // Check permissions
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

      // Start accelerometer stream
      _accelStream = accelerometerEvents.listen(
            (event) {
          if (isClosed) return;

          // Compute motion magnitude (remove gravity)
          final mag = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
          final motion = (mag - SpeedConfig.gravityMagnitude).abs();

          // Apply noise filter
          _accMagnitude = motion < SpeedConfig.accelNoiseFilter ? 0.0 : motion;
        },
        onError: (error) {
          if (!isClosed) {
            add(StopTracking());
            emit(SpeedError("Accelerometer error: $error"));
          }
        },
      );

      // Start GPS stream
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen(
            (pos) {
          if (isClosed) return;

          _gpsSpeed = pos.speed * 3.6; // m/s → km/h
          _lastGpsUpdate = DateTime.now();
        },
        onError: (error) {
          if (!isClosed) {
            // Don't stop tracking on GPS errors, just mark as stale
            _lastGpsUpdate = null;
          }
        },
      );

      // Start sensor fusion timer
      _fusionTimer = Timer.periodic(
        SpeedConfig.fusionUpdateInterval,
            (timer) {
          if (isClosed) {
            timer.cancel();
            return;
          }

          // Check if GPS data is stale
          final gpsStale = _lastGpsUpdate == null ||
              DateTime.now().difference(_lastGpsUpdate!).inMilliseconds >
                  SpeedConfig.gpsStaleThresholdMs;

          // Compute fused speed
          double fusedSpeed;
          if (gpsStale) {
            // GPS unavailable - use accelerometer prediction
            fusedSpeed = _currentSpeed +
                _accMagnitude * SpeedConfig.accelMultiplier;
          } else {
            // Combine GPS + accelerometer
            fusedSpeed = (_gpsSpeed * SpeedConfig.gpsWeight) +
                (_accMagnitude * SpeedConfig.accelWeight);
          }

          // Apply Kalman smoothing
          double filtered = _kalman.filter(fusedSpeed);

          // Detect stationary state
          if (filtered < SpeedConfig.stationarySpeedThreshold &&
              _accMagnitude < SpeedConfig.stationaryAccelThreshold) {
            filtered = 0.0;
            _kalman.reset();
          }

          // Clamp to valid range
          filtered = filtered.clamp(0.0, SpeedConfig.maxSpeed);
          _currentSpeed = filtered;

          // Emit update
          if (!isClosed) {
            add(_SpeedUpdate(_currentSpeed));
          }
        },
      );
    } catch (e) {
      emit(SpeedError("Speed tracking error: $e"));
      await _cleanup();
    }
  }

  Future<void> _onStopTracking(
      StopTracking event, Emitter<SpeedState> emit) async {
    await _cleanup();
    emit(SpeedInitial());
  }

  /// Clean up all resources
  Future<void> _cleanup() async {
    await _positionStream?.cancel();
    _positionStream = null;

    await _accelStream?.cancel();
    _accelStream = null;

    _fusionTimer?.cancel();
    _fusionTimer = null;

    _currentSpeed = 0.0;
    _accMagnitude = 0.0;
    _gpsSpeed = 0.0;
    _lastGpsUpdate = null;
    _kalman.reset();
  }

  @override
  Future<void> close() async {
    await _cleanup();
    return super.close();
  }
}
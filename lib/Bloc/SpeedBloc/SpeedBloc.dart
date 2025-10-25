import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

// --- Events ---
abstract class SpeedEvent {}
class StartTracking extends SpeedEvent {}
class StopTracking extends SpeedEvent {}
class _SpeedUpdateInternal extends SpeedEvent {
  final double speedKmh;
  _SpeedUpdateInternal(this.speedKmh);
}

// --- States ---
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

// --- Bloc ---
class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  // Subscriptions for managing sensor/GPS streams
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<AccelerometerEvent>? _accelStream;

  // Current state variables
  double _currentSpeed = 0.0; // The filtered speed in km/h
  double _rawAccelMagnitude = 0.0; // Raw acceleration magnitude for stationary check

  // Constants
  static const double _kmhFactor = 3.6; // m/s to km/h conversion
  static const double _stationaryThresholdKmh = 1.0; // Below this speed, consider using accel data
  static const double _rawGpsCheckThresholdKmh = 2.0; // Raw GPS speed must also be below this to apply accel check
  static const double _accelMovementThreshold = 0.15; // m/s^2 for physical movement detection

  // --- HIGH-RESPONSIVENESS TUNING ---
  // A lower value makes the filter more aggressive and responsive (less delay).
  // This is the final optimized value.
  static const double _gpsTrustFactor = 0.04;

  // --- EMISSION THROTTLING CONSTANT ---
  // The BLoC will only emit a new state if the new speed is different by more than this value.
  // This is the final optimized value for "instant" text updates.
  static const double _speedUpdateThreshold = 0.005;


  SpeedBloc() : super(SpeedInitial()) {
    on<StartTracking>(_onStartTracking);
    on<StopTracking>(_onStopTracking);
    on<_SpeedUpdateInternal>((event, emit) {
      if (!isClosed) {
        // We only emit a new state if the speed change is greater than the minimal threshold,
        // preventing unnecessary widget rebuilds from minor floating-point jitter.
        if ((event.speedKmh - _currentSpeed).abs() > _speedUpdateThreshold) {
          _currentSpeed = event.speedKmh;
          emit(SpeedUpdated(_currentSpeed));
        } else if (state is! SpeedUpdated) {
          // Ensure the initial 0.0 speed is always emitted when tracking starts
          _currentSpeed = event.speedKmh;
          emit(SpeedUpdated(_currentSpeed));
        }
      }
    });
  }

  /// Handles permissions and starts the GPS and Accelerometer streams.
  Future<void> _onStartTracking(StartTracking event, Emitter<SpeedState> emit) async {
    emit(SpeedLoading());

    try {
      if (!await _checkAndRequestPermissions(emit)) return;

      // Start the accelerometer listener
      _startAccelerometerStream();

      // Start the GPS listener
      _startGpsStream();

    } catch (e) {
      emit(SpeedError("Failed to start tracking: ${e.toString()}"));
    }
  }

  /// Checks for location service status and requests necessary permissions.
  Future<bool> _checkAndRequestPermissions(Emitter<SpeedState> emit) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      emit(SpeedError("Location services are disabled. Please enable them."));
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        emit(SpeedError("Location permissions are denied."));
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      emit(SpeedError("Location permissions permanently denied."));
      return false;
    }
    return true;
  }

  /// Starts listening to accelerometer events for stationary checks.
  void _startAccelerometerStream() {
    _accelStream?.cancel();
    // Use raw accelerometer to calculate total magnitude (G-force vector length)
    // This is simpler and sufficient for a stationary check.
    _accelStream = accelerometerEvents.listen((event) {
      _rawAccelMagnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    });
  }

  /// Starts listening to GPS position stream and applies dynamic fusion.
  void _startGpsStream() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        // Set distanceFilter to 0 for maximum frequency updates (Realtime)
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      final double gpsKmh = pos.speed * _kmhFactor;
      double newFilteredSpeed = _currentSpeed;

      // 1. Initial State Check: If this is the first valid reading, use it directly.
      if (state is SpeedLoading || state is SpeedInitial) {
        newFilteredSpeed = gpsKmh;
      } else {
        // 2. Dynamic Fusion (Kalman-like approach with inverse accuracy weighting)
        final double accuracy = pos.accuracy.clamp(1.0, 30.0); // Clamp accuracy for stable weights

        // Calculate a weight (W) for the new GPS reading.
        // A lower _gpsTrustFactor makes the weight higher, increasing responsiveness.
        final double weight = 1.0 / (1.0 + _gpsTrustFactor * accuracy);

        // Apply the weighted average (fusion filter)
        newFilteredSpeed = _currentSpeed * (1.0 - weight) + gpsKmh * weight;
      }

      // 3. Stationary Override
      // This essential check remains to maintain a stable 0.0 km/h reading when stopped.
      // We check BOTH the filtered speed AND the raw GPS speed to prevent bugs at low speed.
      if (newFilteredSpeed < _stationaryThresholdKmh && gpsKmh < _rawGpsCheckThresholdKmh) {
        final double deltaG = (_rawAccelMagnitude - 9.81).abs();

        if (deltaG < _accelMovementThreshold) {
          newFilteredSpeed = 0.0;
        }
      }

      // 4. Send the new speed to the BLoC
      if (!isClosed) {
        add(_SpeedUpdateInternal(newFilteredSpeed.clamp(0.0, 300.0)));
      }

    }, onError: (e) {
      // Log or handle stream errors gracefully
      print("GPS Stream Error: $e");
    });
  }

  /// Cancels streams and resets the state.
  Future<void> _onStopTracking(StopTracking event, Emitter<SpeedState> emit) async {
    await _positionStream?.cancel();
    await _accelStream?.cancel();
    _currentSpeed = 0.0;
    _rawAccelMagnitude = 0.0;
    emit(SpeedInitial());
  }

  @override
  Future<void> close() {
    _positionStream?.cancel();
    _accelStream?.cancel();
    return super.close();
  }
}


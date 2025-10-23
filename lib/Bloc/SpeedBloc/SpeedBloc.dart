import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Events
abstract class SpeedEvent {}
class StartTracking extends SpeedEvent {}
class StopTracking extends SpeedEvent {}
class _SpeedUpdate extends SpeedEvent {
  final double speedKmh;
  _SpeedUpdate(this.speedKmh);
}

/// States
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

/// BLoC
class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<AccelerometerEvent>? _accelStream;

  double _currentSpeed = 0.0;
  double _accMagnitude = 0.0;

  SpeedBloc() : super(SpeedInitial()) {
    on<StartTracking>(_onStartTracking);
    on<StopTracking>(_onStopTracking);
    on<_SpeedUpdate>((event, emit) => emit(SpeedUpdated(event.speedKmh)));
  }

  Future<void> _onStartTracking(StartTracking event, Emitter<SpeedState> emit) async {
    emit(SpeedLoading());

    try {
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
            "Location permissions are permanently denied. Please enable them in settings."));
        return;
      }

      // Accelerometer stream
      _accelStream?.cancel();
      _accelStream = accelerometerEvents.listen((event) {
        _accMagnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      });

      // GPS stream
      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        double gpsKmh = pos.speed * 3.6;
        // Filter: if GPS reports tiny speed but phone is stationary, set 0
        if (gpsKmh < 1.0 && _accMagnitude < 0.1) gpsKmh = 0.0;

        // Smooth the speed using simple low-pass filter
        _currentSpeed = _currentSpeed + (gpsKmh - _currentSpeed) * 0.2;

        if (!isClosed) add(_SpeedUpdate(_currentSpeed));
      });
    } catch (e) {
      emit(SpeedError(e.toString()));
    }
  }

  Future<void> _onStopTracking(StopTracking event, Emitter<SpeedState> emit) async {
    await _positionStream?.cancel();
    await _accelStream?.cancel();
    _currentSpeed = 0.0;
    _accMagnitude = 0.0;
    emit(SpeedInitial());
  }

  @override
  Future<void> close() {
    _positionStream?.cancel();
    _accelStream?.cancel();
    return super.close();
  }
}

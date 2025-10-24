import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

abstract class SpeedEvent {}
class StartTracking extends SpeedEvent {}
class StopTracking extends SpeedEvent {}
class _SpeedUpdate extends SpeedEvent {
  final double speedKmh;
  _SpeedUpdate(this.speedKmh);
}

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

class SpeedBloc extends Bloc<SpeedEvent, SpeedState> {
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<AccelerometerEvent>? _accelStream;

  double _currentSpeed = 0.0;
  double _accMagnitude = 0.0;
  double _gravityX = 0, _gravityY = 0, _gravityZ = 0;

  SpeedBloc() : super(SpeedInitial()) {
    on<StartTracking>(_onStartTracking);
    on<StopTracking>(_onStopTracking);
    on<_SpeedUpdate>((event, emit) {
      if (!isClosed) emit(SpeedUpdated(event.speedKmh));
    });
  }

  Future<void> _onStartTracking(StartTracking event, Emitter<SpeedState> emit) async {
    emit(SpeedLoading());

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        emit(SpeedError("Location services are disabled."));
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          emit(SpeedError("Location permissions are denied."));
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        emit(SpeedError("Location permissions permanently denied."));
        return;
      }

      // Accelerometer listener (gravity-compensated)
      const alpha = 0.8;
      _accelStream?.cancel();
      _accelStream = accelerometerEvents.listen((event) {
        _gravityX = alpha * _gravityX + (1 - alpha) * event.x;
        _gravityY = alpha * _gravityY + (1 - alpha) * event.y;
        _gravityZ = alpha * _gravityZ + (1 - alpha) * event.z;

        final linearX = event.x - _gravityX;
        final linearY = event.y - _gravityY;
        final linearZ = event.z - _gravityZ;

        _accMagnitude = sqrt(linearX * linearX + linearY * linearY + linearZ * linearZ);
      });

      // GPS listener
      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).listen((pos) {
        double gpsKmh = pos.speed * 3.6;

        // Sanity checks
        if (pos.accuracy > 25) return;
        if (gpsKmh < 0 || gpsKmh > 300) return;
        if ((gpsKmh - _currentSpeed).abs() > 50) return;

        // If stationary, zero speed
        if (gpsKmh < 1.0 && _accMagnitude < 0.15) gpsKmh = 0.0;

        // Smooth speed with exponential filter
        const smoothing = 0.1;
        _currentSpeed = _currentSpeed * (1 - smoothing) + gpsKmh * smoothing;

        if (!isClosed) add(_SpeedUpdate(_currentSpeed));
      });
    } catch (e) {
      emit(SpeedError(e.toString()));
    }
  }

  Future<void> _onStopTracking(StopTracking event, Emitter<SpeedState> emit) async {
    await _positionStream?.cancel();
    await _accelStream?.cancel();
    _currentSpeed = 0;
    emit(SpeedInitial());
  }

  @override
  Future<void> close() {
    _positionStream?.cancel();
    _accelStream?.cancel();
    return super.close();
  }
}

import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';

/// Events
abstract class SpeedLimitEvent {}
class LoadSpeedLimit extends SpeedLimitEvent {}
class UpdateSpeedLimit extends SpeedLimitEvent {
  final double limitKmh;
  UpdateSpeedLimit(this.limitKmh);
}
class CheckSpeed extends SpeedLimitEvent {
  final double currentSpeed;
  CheckSpeed(this.currentSpeed);
}

/// States
abstract class SpeedLimitState {}
class SpeedLimitInitial extends SpeedLimitState {}
class SpeedLimitLoaded extends SpeedLimitState {
  final double limitKmh;
  SpeedLimitLoaded(this.limitKmh);
}
class SpeedLimitAlert extends SpeedLimitState {
  final double speedKmh;
  final double limitKmh;
  SpeedLimitAlert(this.speedKmh, this.limitKmh);
}

/// BLoC
class SpeedLimitBloc extends Bloc<SpeedLimitEvent, SpeedLimitState> {
  final AudioPlayer _player = AudioPlayer();
  double _limitKmh = 60.0; // default
  bool _alertPlaying = false;

  SpeedLimitBloc() : super(SpeedLimitInitial()) {
    on<LoadSpeedLimit>(_onLoadLimit);
    on<UpdateSpeedLimit>(_onUpdateLimit);
    on<CheckSpeed>(_onCheckSpeed);
  }

  Future<void> _onLoadLimit(
      LoadSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    _limitKmh = prefs.getDouble('speed_limit') ?? 60.0;
    emit(SpeedLimitLoaded(_limitKmh));
  }

  Future<void> _onUpdateLimit(
      UpdateSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    _limitKmh = event.limitKmh;
    await prefs.setDouble('speed_limit', _limitKmh);
    emit(SpeedLimitLoaded(_limitKmh));
  }

  Future<void> _onCheckSpeed(
      CheckSpeed event, Emitter<SpeedLimitState> emit) async {
    if (event.currentSpeed >= _limitKmh) {
      emit(SpeedLimitAlert(event.currentSpeed, _limitKmh));

      // Play alert if not already playing
      if (!_alertPlaying) {
        _alertPlaying = true;
        try {
          await _player.setAsset('assets/alert-33762.mp3'); // local audio
          await _player.play();
          if (await Vibration.hasVibrator() ?? false) {
            Vibration.vibrate(duration: 200, amplitude: 128);
          }
        } catch (e) {
          print("Error playing alert: $e");
        } finally {
          _alertPlaying = false;
        }
      }
    }
  }

  @override
  Future<void> close() {
    _player.dispose();
    return super.close();
  }
}

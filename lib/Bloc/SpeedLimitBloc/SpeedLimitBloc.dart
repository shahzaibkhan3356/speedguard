import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:rxdart/rxdart.dart'; // <- rxdart import

/// EVENTS
abstract class SpeedLimitEvent {}
class LoadSpeedLimit extends SpeedLimitEvent {}
class UpdateSpeedLimit extends SpeedLimitEvent { final double limitKmh; UpdateSpeedLimit(this.limitKmh); }
class CheckSpeed extends SpeedLimitEvent { final double currentSpeed; CheckSpeed(this.currentSpeed); }
class StopAlert extends SpeedLimitEvent {}

/// STATES
abstract class SpeedLimitState {}
class SpeedLimitInitial extends SpeedLimitState {}
class SpeedLimitLoaded extends SpeedLimitState { final double limitKmh; SpeedLimitLoaded(this.limitKmh); }
class SpeedWithinLimit extends SpeedLimitState { final double currentSpeed; final double limitKmh; SpeedWithinLimit(this.currentSpeed, this.limitKmh); }
class SpeedLimitWarning extends SpeedLimitState { final double currentSpeed; final double limitKmh; SpeedLimitWarning(this.currentSpeed, this.limitKmh); }
class SpeedLimitExceeded extends SpeedLimitState { final double currentSpeed; final double limitKmh; SpeedLimitExceeded(this.currentSpeed, this.limitKmh); }

/// BLOC
class SpeedLimitBloc extends Bloc<SpeedLimitEvent, SpeedLimitState> {
  final AudioPlayer _player = AudioPlayer();
  double _limitKmh = 0;
  bool _alertPlaying = false;
  DateTime? _lastAlertTime;

  SpeedLimitBloc() : super(SpeedLimitInitial()) {
    on<LoadSpeedLimit>(_onLoadLimit);
    on<UpdateSpeedLimit>(_onUpdateLimit);
    // Use the rxdart-based debounce transformer
    on<CheckSpeed>(_onCheckSpeed, transformer: _debounce<CheckSpeed>(const Duration(milliseconds: 500)));
    on<StopAlert>(_onStopAlert);
  }

  /// Generic debounce transformer using rxdart
  EventTransformer<E> _debounce<E>(Duration duration) {
    return (events, mapper) => events.debounceTime(duration).asyncExpand(mapper);
  }

  Future<void> _onLoadLimit(LoadSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    _limitKmh = prefs.getDouble('speed_limit') ?? 0;
    emit(SpeedLimitLoaded(_limitKmh));
  }

  Future<void> _onUpdateLimit(UpdateSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    _limitKmh = event.limitKmh;
    await prefs.setDouble('speed_limit', _limitKmh);
    emit(SpeedLimitLoaded(_limitKmh));
  }

  Future<void> _onCheckSpeed(CheckSpeed event, Emitter<SpeedLimitState> emit) async {
    final currentSpeed = event.currentSpeed;

    // Simple noise guard
    if (currentSpeed < 1.0) {
      add(StopAlert());
      emit(SpeedWithinLimit(currentSpeed, _limitKmh));
      return;
    }

    // safe zone
    if (currentSpeed < _limitKmh * 0.9) {
      add(StopAlert());
      emit(SpeedWithinLimit(currentSpeed, _limitKmh));
      return;
    }

    // approaching
    if (currentSpeed >= _limitKmh * 0.9 && currentSpeed < _limitKmh) {
      emit(SpeedLimitWarning(currentSpeed, _limitKmh));
      return;
    }

    // exceeded
    if (currentSpeed >= _limitKmh) {
      emit(SpeedLimitExceeded(currentSpeed, _limitKmh));
      await _triggerAlert(currentSpeed);
    }
  }

  Future<void> _onStopAlert(StopAlert event, Emitter<SpeedLimitState> emit) async {
    if (_alertPlaying) {
      try { await _player.stop(); } catch (_) {}
      _alertPlaying = false;
    }
  }

  Future<void> _triggerAlert(double currentSpeed) async {
    final now = DateTime.now();
    if (_lastAlertTime != null && now.difference(_lastAlertTime!).inSeconds < 3) return;
    _lastAlertTime = now;

    if (!_alertPlaying) {
      _alertPlaying = true;
      try {
        await _player.setAsset('assets/alert-33762.mp3');
        await _player.play();
        Get.snackbar("Speed Limit", "Speed Limit Reached",snackPosition: SnackPosition.BOTTOM,backgroundColor: Colors.red);
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 300, amplitude: 200);
        }
      } catch (e) {
        // handle playback error
        print("Alert playback error: $e");
      } finally {
        _alertPlaying = false;
      }
    }
  }
  @override
  Future<void> close() async {
    await _player.dispose();
    return super.close();
  }
}

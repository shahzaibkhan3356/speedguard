import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../../Bloc/SpeedBloc/SpeedBloc.dart'; // 👈 Import SpeedBloc

/// ------------------------------
/// App Assets
/// ------------------------------
class AppAssets {
  static const String alertSound = 'assets/alert-33762.mp3';
}

/// ------------------------------
/// Speed Limit BLoC
/// ------------------------------
class SpeedLimitBloc extends Bloc<SpeedLimitEvent, SpeedLimitState> {
  final Stream<SpeedState> speedStream;
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _speedSub;
  double _limitKmh = 0;

  bool _alertPlaying = false;
  Timer? _alertTimer;

  SpeedLimitBloc({required this.speedStream}) : super(SpeedLimitInitial()) {
    on<LoadSpeedLimit>(_onLoadLimit);
    on<UpdateSpeedLimit>(_onUpdateLimit);
    on<_InternalSpeedCheck>(_onSpeedCheck);
    on<StopAlert>(_onStopAlert);
  }

  /// ------------------------------
  /// Listen to SpeedBloc stream
  /// ------------------------------
  void startListeningToSpeed() {
    _speedSub = speedStream.listen((state) {
      if (state is SpeedUpdated) {
        add(_InternalSpeedCheck(state.speedKmh));
      }
    });
  }

  /// ------------------------------
  /// Load saved speed limit
  /// ------------------------------
  Future<void> _onLoadLimit(
      LoadSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    _limitKmh = prefs.getDouble('speed_limit') ?? 0.0;
    emit(SpeedLimitLoaded(_limitKmh));
  }

  /// ------------------------------
  /// Update speed limit
  /// ------------------------------
  Future<void> _onUpdateLimit(
      UpdateSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    _limitKmh = event.limitKmh;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speed_limit', _limitKmh);
    emit(SpeedLimitLoaded(_limitKmh));
  }

  /// ------------------------------
  /// Handle speed updates
  /// ------------------------------
  Future<void> _onSpeedCheck(
      _InternalSpeedCheck event, Emitter<SpeedLimitState> emit) async {
    final speed = event.speedKmh;

    if (_limitKmh <= 0) {
      emit(SpeedWithinLimit(speed, _limitKmh));
      return;
    }

    if (speed < 1) {
      add(StopAlert());
      emit(SpeedWithinLimit(speed, _limitKmh));
      return;
    }

    if (speed < _limitKmh) {
      add(StopAlert());
      emit(SpeedWithinLimit(speed, _limitKmh));
    } else {
      emit(SpeedLimitExceeded(speed, _limitKmh));
      await _triggerContinuousAlert(speed);
    }
  }

  /// ------------------------------
  /// Continuous alert (looping until stopped)
  /// ------------------------------
  Future<void> _triggerContinuousAlert(double speed) async {
    if (_alertPlaying) return;
    _alertPlaying = true;
    try {
      await _player.setAsset(AppAssets.alertSound);
      await _player.setLoopMode(LoopMode.one); // 🔁 Loop sound
      await _player.play();
      _alertTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        Get.snackbar(
          "Speed Limit Exceeded 🚨",
          "Current speed: ${speed.toStringAsFixed(1)} km/h",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withOpacity(0.9),
          colorText: Colors.white,
          duration: const Duration(seconds: 1),
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
        );
      });
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 500, amplitude: 255);
      }
    } catch (e) {
      debugPrint("Alert error: $e");
      _alertPlaying = false;
    }
  }

  /// ------------------------------
  /// Stop alert
  /// ------------------------------
  Future<void> _onStopAlert(
      StopAlert event, Emitter<SpeedLimitState> emit) async {
    if (_alertPlaying) {
      try {
        await _player.stop();
      } catch (_) {}
      _alertPlaying = false;
      _alertTimer?.cancel();
      _alertTimer = null;
    }
  }

  /// ------------------------------
  /// Dispose resources
  /// ------------------------------
  @override
  Future<void> close() async {
    await _speedSub?.cancel();
    await _player.dispose();
    return super.close();
  }
}

/// ------------------------------
/// EVENTS
/// ------------------------------
abstract class SpeedLimitEvent {}

class LoadSpeedLimit extends SpeedLimitEvent {}

class UpdateSpeedLimit extends SpeedLimitEvent {
  final double limitKmh;
  UpdateSpeedLimit(this.limitKmh);
}

class StopAlert extends SpeedLimitEvent {}

class _InternalSpeedCheck extends SpeedLimitEvent {
  final double speedKmh;
  _InternalSpeedCheck(this.speedKmh);
}

/// ------------------------------
/// STATES
/// ------------------------------
abstract class SpeedLimitState {}

class SpeedLimitInitial extends SpeedLimitState {}

class SpeedLimitLoaded extends SpeedLimitState {
  final double limitKmh;
  SpeedLimitLoaded(this.limitKmh);
}

class SpeedWithinLimit extends SpeedLimitState {
  final double currentSpeed;
  final double limitKmh;
  SpeedWithinLimit(this.currentSpeed, this.limitKmh);
}

class SpeedLimitExceeded extends SpeedLimitState {
  final double currentSpeed;
  final double limitKmh;
  SpeedLimitExceeded(this.currentSpeed, this.limitKmh);
}

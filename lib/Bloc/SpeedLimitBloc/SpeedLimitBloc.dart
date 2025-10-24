import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:rxdart/rxdart.dart';

/// App assets constants
class AppAssets {
  static const String alertSound = 'assets/alert-33762.mp3';
}

/// Speed limit configuration
class SpeedLimitConfig {
  static const double minimumWarningThreshold = 5.0; // km/h
  static const double warningRatio = 0.9; // 90% of limit
  static const int alertCooldownSeconds = 3;
  static const Duration debounceDuration = Duration(milliseconds: 500);
}

/// EVENTS
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

class StopAlert extends SpeedLimitEvent {}

/// STATES
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

class SpeedLimitWarning extends SpeedLimitState {
  final double currentSpeed;
  final double limitKmh;
  SpeedLimitWarning(this.currentSpeed, this.limitKmh);
}

class SpeedLimitExceeded extends SpeedLimitState {
  final double currentSpeed;
  final double limitKmh;
  SpeedLimitExceeded(this.currentSpeed, this.limitKmh);
}

/// BLoC for managing speed limit alerts
///
/// Monitors current speed against a user-defined limit and triggers
/// audio/visual/haptic alerts when exceeded.
class SpeedLimitBloc extends Bloc<SpeedLimitEvent, SpeedLimitState> {
  final AudioPlayer _player = AudioPlayer();
  double _limitKmh = 0;
  bool _alertPlaying = false;
  DateTime? _lastAlertTime;
  StreamSubscription? _playerSubscription;

  SpeedLimitBloc() : super(SpeedLimitInitial()) {
    on<LoadSpeedLimit>(_onLoadLimit);
    on<UpdateSpeedLimit>(_onUpdateLimit);
    on<CheckSpeed>(
      _onCheckSpeed,
      transformer: _debounce<CheckSpeed>(SpeedLimitConfig.debounceDuration),
    );
    on<StopAlert>(_onStopAlert);

    // Listen to player state to properly manage _alertPlaying flag
    _playerSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed ||
          state.processingState == ProcessingState.idle) {
        _alertPlaying = false;
      }
    });
  }

  /// Generic debounce transformer using rxdart
  EventTransformer<E> _debounce<E>(Duration duration) {
    return (events, mapper) => events.debounceTime(duration).asyncExpand(mapper);
  }

  Future<void> _onLoadLimit(
      LoadSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _limitKmh = prefs.getDouble('speed_limit') ?? 0;
      emit(SpeedLimitLoaded(_limitKmh));
    } catch (e) {
      debugPrint("Error loading speed limit: $e");
      emit(SpeedLimitLoaded(0));
    }
  }

  Future<void> _onUpdateLimit(
      UpdateSpeedLimit event, Emitter<SpeedLimitState> emit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _limitKmh = event.limitKmh;
      await prefs.setDouble('speed_limit', _limitKmh);
      emit(SpeedLimitLoaded(_limitKmh));
    } catch (e) {
      debugPrint("Error saving speed limit: $e");
      emit(SpeedLimitLoaded(_limitKmh)); // Keep current value
    }
  }

  Future<void> _onCheckSpeed(
      CheckSpeed event, Emitter<SpeedLimitState> emit) async {
    final currentSpeed = event.currentSpeed;

    // If no limit set, stay within limit
    if (_limitKmh <= 0) {
      emit(SpeedWithinLimit(currentSpeed, _limitKmh));
      return;
    }

    // Simple noise guard - very low speeds
    if (currentSpeed < 1.0) {
      add(StopAlert());
      emit(SpeedWithinLimit(currentSpeed, _limitKmh));
      return;
    }

    // Calculate warning threshold (90% of limit, but at least 5 km/h below)
    final warningThreshold = (_limitKmh * SpeedLimitConfig.warningRatio)
        .clamp(SpeedLimitConfig.minimumWarningThreshold, _limitKmh);

    // Determine state based on speed
    if (currentSpeed < warningThreshold) {
      // Safe zone
      add(StopAlert());
      emit(SpeedWithinLimit(currentSpeed, _limitKmh));
    } else if (currentSpeed < _limitKmh) {
      // Approaching limit
      emit(SpeedLimitWarning(currentSpeed, _limitKmh));
    } else {
      // Limit exceeded
      emit(SpeedLimitExceeded(currentSpeed, _limitKmh));
      await _triggerAlert(currentSpeed);
    }
  }

  Future<void> _onStopAlert(
      StopAlert event, Emitter<SpeedLimitState> emit) async {
    if (_alertPlaying) {
      try {
        await _player.stop();
      } catch (e) {
        debugPrint("Error stopping alert: $e");
      }
      _alertPlaying = false;
    }
  }

  Future<void> _triggerAlert(double currentSpeed) async {
    // Cooldown check
    final now = DateTime.now();
    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!).inSeconds <
            SpeedLimitConfig.alertCooldownSeconds) {
      return;
    }

    // Prevent multiple simultaneous alerts
    if (_alertPlaying) return;

    _lastAlertTime = now;
    _alertPlaying = true;

    try {
      // Stop any previous playback
      await _player.stop();

      // Load and play alert sound
      await _player.setAsset(AppAssets.alertSound);
      await _player.play();

      // Show snackbar notification
      Get.snackbar(
        "Speed Limit Exceeded",
        "Current speed: ${currentSpeed.toInt()} km/h",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(8),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      );

      // Trigger vibration if available
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 300, amplitude: 200);
      }
    } catch (e) {
      debugPrint("Alert playback error: $e");
      _alertPlaying = false;

      // Fallback: show notification even if sound fails
      Get.snackbar(
        "Speed Limit Exceeded",
        "Current speed: ${currentSpeed.toInt()} km/h (Sound unavailable)",
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(8),
      );
    }
  }

  @override
  Future<void> close() async {
    await _playerSubscription?.cancel();
    await _player.dispose();
    return super.close();
  }
}
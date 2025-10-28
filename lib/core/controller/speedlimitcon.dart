import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speedguard/Bloc/SpeedBloc/SpeedBloc.dart';
import 'package:vibration/vibration.dart';

/// A dedicated controller that listens to SpeedCubit and handles
/// real-time alerts (sound, vibration, and UI flash/snackbar)
class SpeedAlertController {
  final SpeedCubit speedCubit;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<SpeedState>? _sub;
  bool _alertActive = false;
  Timer? _snackbarTimer;

  /// Used by UI to flash the red overlay
  final ValueNotifier<bool> isFlashing = ValueNotifier(false);

  SpeedAlertController(this.speedCubit) {
    _listenToSpeedChanges();
  }

  void _listenToSpeedChanges() {
    _sub = speedCubit.stream.listen((state) async {
      if (state.overSpeed && state.isMoving) {
        if (!_alertActive) {
          _alertActive = true;
          _startAlerts(state);
        }
      } else if (_alertActive && (!state.overSpeed || !state.isMoving)) {
        _stopAlerts();
      }
    });
  }

  /// Start synchronized alerts
  Future<void> _startAlerts(SpeedState state) async {
    _toggleFlash(true);

    if (state.soundEnabled) _startSound();
    if (state.vibrationEnabled) _startVibration();
    _startSnackbar(state);
  }

  /// Stop all alerts immediately
  Future<void> _stopAlerts() async {
    _alertActive = false;
    _toggleFlash(false);
    _snackbarTimer?.cancel();
    await _stopSound();
    await _stopVibration();
    Get.closeAllSnackbars();
  }

  /// Flash notifier (used by UI background)
  void _toggleFlash(bool value) {
    isFlashing.value = value;
  }

  /// Periodic snackbar for visual alert
  void _startSnackbar(SpeedState state) {
    _snackbarTimer?.cancel();
    _snackbarTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_alertActive) return;

      Get.closeAllSnackbars();
      Get.snackbar(
        "Speed Limit 🚨",
        "You're over the limit (${state.filteredSpeed.toStringAsFixed(1)} ${state.useMph ? "mph" : "km/h"})",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 1),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
      );
    });
  }

  /// Continuous sound alert
  Future<void> _startSound() async {
    try {
      await _audioPlayer.setAsset("assets/alert-33762.mp3");
      await _audioPlayer.setLoopMode(LoopMode.one);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("⚠️ Sound error: $e");
    }
  }

  Future<void> _stopSound() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  /// Continuous vibration while speeding
  Future<void> _startVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 700, 300], repeat: 0);
    }
  }

  Future<void> _stopVibration() async {
    try {
      if (await Vibration.hasVibrator() ?? false) Vibration.cancel();
    } catch (_) {}
  }

  /// Cleanup resources
  Future<void> dispose() async {
    await _sub?.cancel();
    _snackbarTimer?.cancel();
    await _stopSound();
    await _stopVibration();
    await _audioPlayer.dispose();
  }
}

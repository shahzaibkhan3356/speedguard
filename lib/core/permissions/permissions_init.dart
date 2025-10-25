import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speedguard/features/dashboard/dashboard.dart';

/// Permission initialization screen
///
/// Handles requesting and validating all required permissions before
/// allowing access to the main speedometer screen.
class PermissionInitializer extends StatefulWidget {
  const PermissionInitializer({super.key});

  @override
  State<PermissionInitializer> createState() => _PermissionInitializerState();
}

class _PermissionInitializerState extends State<PermissionInitializer>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Detects when user returns from Settings or background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) {
      // Reset dialog flag when returning from settings
      _dialogShown = false;
      _checkPermissionsAndContinue();
    }
  }

  /// Initialize permissions flow
  Future<void> _initialize() async {
    await _requestAllPermissions();
  }

  /// Request all required permissions
  Future<void> _requestAllPermissions() async {
    try {
      final fg = await Permission.locationWhenInUse.request();
      await Permission.notification.request();
      await Permission.audio.request();

      // Check if location permission granted
      if (!fg.isGranted) {
        if (!_dialogShown) {
          _dialogShown = true;
          _showPermissionDialog();
        }
        return;
      }

      // Location permission granted, now check GPS service
      await _checkLocationService();
    } catch (e) {
      if (!_dialogShown && mounted) {
        _dialogShown = true;
        _showErrorDialog("Permission error: $e");
      }
    }
  }

  /// Check if GPS is enabled
  Future<void> _checkLocationService() async {
    try {
      bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!isServiceEnabled) {
        if (!_dialogShown && mounted) {
          _dialogShown = true;
          _showLocationServiceDialog();
        }
        return;
      }

      // All permissions granted and GPS enabled - proceed to main screen
      await _navigateToMainScreen();
    } catch (e) {
      if (!_dialogShown && mounted) {
        _dialogShown = true;
        _showErrorDialog("Location service error: $e");
      }
    }
  }

  /// Recheck permissions when returning from settings
  Future<void> _checkPermissionsAndContinue() async {
    setState(() => _checking = true);

    final fg = await Permission.locationWhenInUse.status;

    if (fg.isGranted) {
      await _checkLocationService();
    } else {
      setState(() => _checking = false);
      if (!_dialogShown) {
        _dialogShown = true;
        _showPermissionDialog();
      }
    }
  }

  /// Navigate to main speed screen
  Future<void> _navigateToMainScreen() async {
    if (mounted) {
      setState(() => _checking = false);

      // Small delay to show ready state
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Get.offAll(() => const DashboardPage());
      }
    }
  }

  /// Show permission denied dialog
  void _showPermissionDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Permissions Required"),
        content: const Text(
          "Location, audio, and notification permissions are required to use this app.\n\n"
          "Please enable them in settings to continue.",
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _dialogShown = false;

              try {
                final opened = await openAppSettings();
                if (!opened) {
                  Fluttertoast.showToast(
                    msg: "Could not open settings. Please open manually.",
                    backgroundColor: Colors.orange,
                    toastLength: Toast.LENGTH_LONG,
                  );
                }
              } catch (e) {
                Fluttertoast.showToast(
                  msg: "Error opening settings: $e",
                  backgroundColor: Colors.red,
                  toastLength: Toast.LENGTH_LONG,
                );
              }
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  /// Show GPS disabled dialog
  void _showLocationServiceDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enable Location Service"),
        content: const Text(
          "Your device GPS is turned off. Please enable it to use the speedometer.",
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _dialogShown = false;

              try {
                await Geolocator.openLocationSettings();
                Fluttertoast.showToast(
                  msg: "Please turn on Location and return to the app.",
                  backgroundColor: Colors.orange,
                  toastLength: Toast.LENGTH_LONG,
                );
              } catch (e) {
                Fluttertoast.showToast(
                  msg: "Could not open location settings: $e",
                  backgroundColor: Colors.red,
                  toastLength: Toast.LENGTH_LONG,
                );
              }
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  /// Show generic error dialog
  void _showErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogShown = false;
              _initialize(); // Retry
            },
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151C),
      body: Center(
        child: _checking
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: Colors.white),
                ],
              )
            : const Text(
                "Ready!",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

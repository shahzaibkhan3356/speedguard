import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speedguard/features/dashboard/dashboard.dart';

/// Handles permission requests and GPS validation before entering main app
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

  /// Detects when app returns from background or Settings
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_checking) {
      _dialogShown = false;
      _checkPermissionsAndContinue();
    }
  }

  /// Initialize permissions and GPS check flow
  Future<void> _initialize() async {
    // ✅ If permissions and GPS already OK, skip checks
    final locationStatus = await Permission.locationWhenInUse.status;
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();

    if (locationStatus.isGranted && gpsEnabled) {
      _navigateToMainScreen();
      return;
    }

    await _requestAllPermissions();
  }

  /// Request location, audio, and notification permissions
  Future<void> _requestAllPermissions() async {
    try {
      final locationStatus = await Permission.locationWhenInUse.request();
      await Permission.notification.request();
      await Permission.audio.request();

      if (!locationStatus.isGranted) {
        if (!_dialogShown) {
          _dialogShown = true;
          _showPermissionDialog();
        }
        return;
      }

      // ✅ Continue if permission granted
      await _checkLocationService();
    } catch (e) {
      if (!_dialogShown && mounted) {
        _dialogShown = true;
        _showErrorDialog("Permission error: $e");
      }
    }
  }

  /// Ensure GPS service is enabled
  Future<void> _checkLocationService() async {
    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!isServiceEnabled) {
        if (!_dialogShown && mounted) {
          _dialogShown = true;
          _showLocationServiceDialog();
        }
        setState(() => _checking = false);
        return;
      }

      // ✅ Everything ready
      if (mounted) {
        setState(() => _checking = false);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Get.offAll(() => const DashboardPage());
      }
    } catch (e) {
      if (!_dialogShown && mounted) {
        _dialogShown = true;
        _showErrorDialog("Location service error: $e");
      }
    }
  }

  /// Recheck when returning from settings
  Future<void> _checkPermissionsAndContinue() async {
    setState(() => _checking = true);
    final locationStatus = await Permission.locationWhenInUse.status;
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();

    if (locationStatus.isGranted && gpsEnabled) {
      await _navigateToMainScreen();
    } else {
      setState(() => _checking = false);
      if (!_dialogShown) {
        _dialogShown = true;
        if (!locationStatus.isGranted) {
          _showPermissionDialog();
        } else {
          _showLocationServiceDialog();
        }
      }
    }
  }

  /// Navigate to main dashboard
  Future<void> _navigateToMainScreen() async {
    if (!mounted) return;
    setState(() => _checking = false);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      Get.offAll(() => const DashboardPage());
    }
  }

  /// Show permission dialog
  void _showPermissionDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        title: const Text(
          "Permissions Required",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Location, audio, and notification permissions are required to use SpeedGuard.\n\n"
          "Please enable them in settings to continue.",
          style: TextStyle(color: Colors.white70),
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
            child: const Text(
              "Open Settings",
              style: TextStyle(color: Colors.tealAccent),
            ),
          ),
        ],
      ),
    );
  }

  /// Show GPS off dialog
  void _showLocationServiceDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        title: const Text("Enable GPS", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Your device's GPS is turned off.\nPlease enable it to continue using SpeedGuard.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _dialogShown = false;

              try {
                await Geolocator.openLocationSettings();
                Fluttertoast.showToast(
                  msg: "Please enable GPS and return to the app.",
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
            child: const Text(
              "Open Settings",
              style: TextStyle(color: Colors.tealAccent),
            ),
          ),
        ],
      ),
    );
  }

  /// Generic error dialog
  void _showErrorDialog(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D24),
        title: const Text("Error", style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _dialogShown = false;
              _initialize();
            },
            child: const Text(
              "Retry",
              style: TextStyle(color: Colors.tealAccent),
            ),
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
                  CircularProgressIndicator(color: Colors.tealAccent),
                  SizedBox(height: 20),
                  Text(
                    "Checking permissions...",
                    style: TextStyle(color: Colors.white70),
                  ),
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

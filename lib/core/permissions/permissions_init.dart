import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speedguard/features/speedometer/speedscreen.dart';

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
    if (state == AppLifecycleState.resumed) {
      _checkLocationService(); // Recheck when returning
    }
  }

  Future<void> _initialize() async {
    await _requestAllPermissions();
    await _checkLocationService();
  }

  /// Ask all required permissions
  Future<void> _requestAllPermissions() async {
    final fg = await Permission.locationWhenInUse.request();
    await Permission.notification.request();
    await Permission.audio.request();

    if (!fg.isGranted && !_dialogShown) {
      _dialogShown = true;
      _showPermissionDialog();
      return;
    }
  }

  /// Check if GPS is ON
  Future<void> _checkLocationService() async {
    bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isServiceEnabled && !_dialogShown) {
      _dialogShown = true;
      _showLocationServiceDialog();
      return;
    }

    // When all okay
    if (mounted) {
      setState(() => _checking = false);
      Get.offAll(const SpeedPage());
    }
  }

  /// Permission dialog
  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Permissions Required"),
        content: const Text(
          "Location, audio, or notification permissions are denied. "
              "Please enable them in settings to use the app.",
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _dialogShown = false;
              await openAppSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  /// GPS disabled dialog
  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enable Location Service"),
        content: const Text(
          "Your device GPS is turned off. Please enable it to continue.",
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _dialogShown = false;
              await Geolocator.openLocationSettings();
              Fluttertoast.showToast(
                msg: "Turn on Location and reopen the app.",
                backgroundColor: Colors.red,
              );
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _checking
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
          "Ready!",
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

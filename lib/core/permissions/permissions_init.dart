import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speedguard/features/speedometer/speedscreen.dart';

class PermissionInitializer extends StatefulWidget {
  const PermissionInitializer({super.key});

  @override
  State<PermissionInitializer> createState() => _PermissionInitializerState();
}

class _PermissionInitializerState extends State<PermissionInitializer> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
  }

  Future<void> _requestAllPermissions() async {
    PermissionStatus fg = await Permission.locationWhenInUse.request();
    PermissionStatus bg = await Permission.locationAlways.request();
    await Permission.notification.request();
    await Permission.audio.request();
    if (fg.isGranted && bg.isGranted) {
      Get.offAll(const SpeedPage());
    } else {
_showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Permissions Required"),
        content: const Text(
            "Some permissions are denied. Please enable them in settings to use the app."),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
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
            : const Text("Permissions granted!"),
      ),
    );
  }
}

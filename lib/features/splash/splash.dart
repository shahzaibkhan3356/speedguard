import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:speedguard/core/permissions/permissions_init.dart';
import 'package:speedguard/core/theme/AppTheme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(
      const Duration(seconds: 4),
      () => Get.offAll(() => const PermissionInitializer()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151C), // 🟩 Same dark tone
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ====== LOTTIE ANIMATION ======
            Lottie.asset(
              'assets/Speedometer.json',
              width: 220,
              height: 220,
              fit: BoxFit.fill,
            ),
            const SizedBox(height: 50),

            // ====== APP TITLE ======
            Text(
              "Speed Guard",
              style: AppTheme.heading1.copyWith(
                color: Colors.tealAccent, // 🟩 Accent like in SettingsPage
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),

            const SizedBox(height: 10),

            // ====== SUBTEXT / TAGLINE ======
            Text(
              "Drive Smart. Stay Safe.",
              style: AppTheme.body.copyWith(
                color: Colors.white60,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

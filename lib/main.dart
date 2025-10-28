import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'Bloc/SpeedBloc/SpeedBloc.dart';
import 'Bloc/ThemeCubit/ThemeCubit.dart';
import 'features/splash/splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only the essential system lock should block UI.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const MyApp());

  // 🔥 Lazy-load heavy async stuff AFTER first frame:
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    unawaited(_initializeBackgroundServices());
  });
}

/// Background async setup — won’t block UI anymore
Future<void> _initializeBackgroundServices() async {
  try {
    await Future.wait([
      MobileAds.instance.initialize(),
      WakelockPlus.enable(),
      SharedPreferences.getInstance(),
    ]);
    debugPrint('[Startup] Background services initialized.');
  } catch (e) {
    debugPrint('[Startup Error] $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SpeedCubit()),
        BlocProvider(create: (_) => ThemeCubit()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeData>(
        builder: (context, theme) {
          return GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

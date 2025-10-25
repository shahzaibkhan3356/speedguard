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
  await MobileAds.instance.initialize();
  await WakelockPlus.enable();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    // DeviceOrientation.portraitDown, // Uncomment if you want upside-down portrait
  ]);
  await SharedPreferences.getInstance(); // ensure ready
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SpeedBloc()..add(StartMeasurement())),
        BlocProvider(create: (_) => ThemeCubit()), // ✅ loads saved theme
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

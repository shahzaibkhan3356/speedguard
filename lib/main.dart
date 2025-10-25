import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:speedguard/core/theme/Apptheme.dart';
import 'package:speedguard/features/splash/splash.dart';

import 'Bloc/SpeedBloc/SpeedBloc.dart';
import 'Bloc/SpeedLimitBloc/SpeedLimitBloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SpeedBloc()..add(StartTracking())),
        BlocProvider(
          create: (context) {
            final speedBloc = context.read<SpeedBloc>();
            final limitBloc = SpeedLimitBloc(speedStream: speedBloc.stream);
            limitBloc.add(LoadSpeedLimit());
            limitBloc.startListeningToSpeed(); // 👈 Sync with SpeedBloc
            return limitBloc;
          },
        ),
      ],
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: SplashScreen(),
      ),
    );
  }
}

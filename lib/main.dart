import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:speedguard/core/theme/Apptheme.dart';
import 'package:speedguard/features/splash/splash.dart';

import 'Bloc/SpeedBloc/SpeedBloc.dart';
import 'Bloc/SpeedLimitBloc/SpeedLimitBloc.dart';
import 'core/permissions/permissions_init.dart';

void main() {
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
        BlocProvider(create: (_) => SpeedLimitBloc()..add(LoadSpeedLimit())),
      ],
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: SplashScreen(),
      ),
    );
  }
}

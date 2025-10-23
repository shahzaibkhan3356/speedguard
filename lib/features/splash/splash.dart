import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:speedguard/core/permissions/permissions_init.dart';
import 'package:speedguard/core/theme/Apptheme.dart';
import 'package:speedguard/features/speedometer/speedscreen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    Future.delayed(Duration(seconds: 4),() {
      Get.offAll(PermissionInitializer());
    },);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
body: Center(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
   Lottie.asset(

     'assets/Speedometer.json',
     width: 200,
     height: 200,
     fit: BoxFit.fill,),
      Container(
        height: 50,
      ),
      Text("Speed Guard",style: AppTheme.heading1,)
    ],
  ),
),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import '../../Bloc/SpeedBloc/SpeedBloc.dart';
import '../../Bloc/SpeedLimitBloc/SpeedLimitBloc.dart';
import '../../core/widgets/bannerad.dart';
import '../../core/widgets/speedlimit.dart';
import '../../core/widgets/speedmeter.dart';

class SpeedPage extends StatelessWidget {
  const SpeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(


        backgroundColor: Colors.black87,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Use SizedBox instead of Expanded
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: Center(
                    child: BlocBuilder<SpeedBloc, SpeedState>(
                      builder: (context, state) {
                        if (state is SpeedUpdated) {
                          return SpeedometerGauge(
                            value: state.speedKmh,
                            min: 0,
                            max: 240,
                            duration: const Duration(milliseconds: 300),
                            units: 'km/h',
                            segments: const [
                              GaugeSegment(to: 120, color: Colors.green),
                              GaugeSegment(to: 180, color: Colors.orange),
                              GaugeSegment(to: 240, color: Colors.red),
                            ],
                            size: MediaQuery.of(context).size.width * 0.8,
                            startAngleDeg: 150,
                            sweepAngleDeg: 240,
                            majorTickCount: 7,
                            minorTicksPerInterval: 4,
                          );
                        }
                        return const CircularProgressIndicator(
                          color: Colors.blueAccent,
                        );
                      },
                    ),
                  ),
                ),

                // Speed limit widget
                const SpeedLimitWidget(),
                const SizedBox(height: 16),

              ],
            ),
          ),
        ),

bottomNavigationBar: AdBannerWidget(),
      ),
    );

  }
}

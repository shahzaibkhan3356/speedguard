import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:speedguard/Bloc/SpeedBloc/SpeedBloc.dart';
import 'package:speedguard/core/controller/speedlimitcon.dart';
import 'package:speedguard/core/theme/Apptheme.dart';
import 'package:speedguard/core/widgets/gpssinglabar.dart';

import '../../core/widgets/bannerad.dart';
import '../../core/widgets/speedmeter.dart';

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key});

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  late final SpeedAlertController _alertController;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<SpeedCubit>();
    _alertController = SpeedAlertController(cubit);
    cubit.start(); // start measuring automatically when page opens
  }

  @override
  void dispose() {
    _alertController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _alertController.isFlashing,
      builder: (context, flashing, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Speedometer",
                  style: AppTheme.title.copyWith(fontSize: 25),
                ),
                const SizedBox(height: 6),
                BlocBuilder<SpeedCubit, SpeedState>(
                  builder: (context, state) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.gps_fixed,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        GpsSignalBars(strength: state.gpsStrength, size: 14),
                        const SizedBox(width: 6),
                        Text("${state.gpsStrength}%", style: AppTheme.title),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          backgroundColor: flashing
              ? Colors.red.withOpacity(0.25)
              : const Color(0xFF12151C),
          body: SafeArea(
            child: Center(
              child: BlocBuilder<SpeedCubit, SpeedState>(
                builder: (context, state) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ===== SPEED GAUGE =====
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1D24),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: SpeedometerGauge(
                            value: state.filteredSpeed,
                            min: 0,
                            max: 240,
                            duration: const Duration(milliseconds: 150),
                            units: state.useMph ? 'mph' : 'km/h',
                            segments: const [
                              GaugeSegment(to: 120, color: Colors.green),
                              GaugeSegment(to: 180, color: Colors.orange),
                              GaugeSegment(to: 240, color: Colors.red),
                            ],
                            size: MediaQuery.of(context).size.width * 0.85,
                            startAngleDeg: 150,
                            sweepAngleDeg: 240,
                            majorTickCount: 7,
                            minorTicksPerInterval: 4,
                          ),
                        ),
                        const SizedBox(height: 30),

                        // ===== SPEED LIMIT CARD =====
                        GestureDetector(
                          onTap: () {
                            Fluttertoast.showToast(
                              msg: "Go to Settings to change Speed Limit",
                              toastLength: Toast.LENGTH_SHORT,
                              gravity: ToastGravity.BOTTOM,
                              backgroundColor: Colors.teal,
                              textColor: Colors.white,
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1D24),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white12,
                                width: 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 20,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Speed Limit",
                                  style: TextStyle(
                                    color: Colors.tealAccent,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  "${state.speedLimit.toInt()} ${state.useMph ? 'mph' : 'km/h'}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ===== STATUS TEXT =====
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: state.overSpeed
                              ? Text(
                                  "⚠️ You are exceeding the speed limit!",
                                  key: const ValueKey("overspeed"),
                                  style: TextStyle(
                                    color: Colors.redAccent.shade200,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : Text(
                                  "Drive Safe!",
                                  key: const ValueKey("safe"),
                                  style: TextStyle(
                                    color: Colors.greenAccent.shade200,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          bottomNavigationBar: const AdBannerWidget(),
        );
      },
    );
  }
}

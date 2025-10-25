import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:speedguard/core/theme/Apptheme.dart';

import '../../Bloc/SpeedBloc/SpeedBloc.dart';
import '../../core/widgets/bannerad.dart';
import '../../core/widgets/speedmeter.dart';

class SpeedPage extends StatelessWidget {
  const SpeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          "Speedometer",
          style: AppTheme.title.copyWith(fontSize: 25),
        ),
      ),
      backgroundColor: const Color(
        0xFF12151C,
      ), // same as SettingsPage background
      body: SafeArea(
        child: Center(
          child: BlocBuilder<SpeedBloc, SpeedState>(
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
                        duration: const Duration(milliseconds: 200),
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
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1D24),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12, width: 1),
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
                  ],
                ),
              );
            },
          ),
        ),
      ),

      // ===== AD BANNER =====
      bottomNavigationBar: const AdBannerWidget(),
    );
  }
}

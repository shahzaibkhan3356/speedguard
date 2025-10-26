import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../Bloc/SpeedBloc/SpeedBloc.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151C),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          physics: const BouncingScrollPhysics(),
          child: BlocConsumer<SpeedBloc, SpeedState>(
            listener: (context, state) {
              // ✅ Whenever bloc updates, sync controller with speed limit
              _controller.text = state.speedLimit.toInt().toString();
            },
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ====== HEADER ======
                  const Center(
                    child: Text(
                      "Settings",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // ====== SPEED LIMIT ======
                  const Text(
                    "Speed Limit",
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1D24),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: TextField(
                            maxLength: 3,
                            controller: _controller,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onSubmitted: (value) {
                              final double? newLimit = double.tryParse(
                                value.trim(),
                              );
                              if (newLimit != null && newLimit > 0) {
                                context.read<SpeedBloc>().add(
                                  UpdateSpeedLimit(newLimit),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          state.useMph ? "mph" : "km/h",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Set the speed limit for alerts  (1–240 ${state.useMph ? "mph" : "km/h"})",
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 24),

                  // ====== UNITS ======
                  const Text(
                    "Units",
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Use mph instead",
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      Switch(
                        activeThumbColor: Colors.tealAccent,
                        value: state.useMph,
                        onChanged: (_) {
                          context.read<SpeedBloc>().add(ToggleSpeedUnit());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ====== ALERTS ======
                  const Text(
                    "Alerts",
                    style: TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Sound Alert
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Sound Alert",
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      Switch(
                        activeThumbColor: Colors.tealAccent,
                        value: state.soundEnabled,
                        onChanged: (_) {
                          context.read<SpeedBloc>().add(ToggleSound());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Vibration Alert
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Vibration Alert",
                        style: TextStyle(color: Colors.white, fontSize: 15),
                      ),
                      Switch(
                        activeThumbColor: Colors.tealAccent,
                        value: state.vibrationEnabled,
                        onChanged: (_) {
                          context.read<SpeedBloc>().add(ToggleVibration());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

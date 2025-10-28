import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:speedguard/Bloc/SpeedBloc/SpeedBloc.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _controller;
  bool _updating = false; // prevent rapid-fire updates

  @override
  void initState() {
    super.initState();
    final cubit = context.read<SpeedCubit>();
    _controller = TextEditingController(
      text: cubit.state.speedLimit.toInt().toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateLimit(String value) {
    if (_updating) return;
    final cubit = context.read<SpeedCubit>();
    final double? newLimit = double.tryParse(value.trim());

    if (newLimit != null && newLimit > 0 && newLimit <= 240) {
      _updating = true;
      cubit.updateSpeedLimit(newLimit);
      Future.delayed(const Duration(milliseconds: 300), () {
        _updating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12151C),
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          physics: const BouncingScrollPhysics(),
          child: BlocBuilder<SpeedCubit, SpeedState>(
            builder: (context, state) {
              // Keep controller in sync but prevent overwriting while editing
              if (!_updating) {
                _controller.text = state.speedLimit.toInt().toString();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ===== SPEED LIMIT =====
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
                            controller: _controller,
                            keyboardType: TextInputType.number,
                            maxLength: 3,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                            ),
                            onChanged: (value) {
                              // Real-time update as user types
                              if (value.isNotEmpty &&
                                  double.tryParse(value) != null) {
                                _updateLimit(value);
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
                    "Set alert threshold (1–240 ${state.useMph ? "mph" : "km/h"})",
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 24),

                  // ===== UNITS =====
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
                          context.read<SpeedCubit>().toggleUnit();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ===== ALERTS =====
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
                          context.read<SpeedCubit>().toggleSound();
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
                          context.read<SpeedCubit>().toggleVibration();
                        },
                      ),
                    ],
                  ),
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

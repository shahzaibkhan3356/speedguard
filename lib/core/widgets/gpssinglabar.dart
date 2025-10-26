import 'package:flutter/material.dart';

class GpsSignalBars extends StatelessWidget {
  final int strength; // 0–100
  final double size;

  const GpsSignalBars({super.key, required this.strength, this.size = 16});

  int _barsFromStrength(int strength) {
    if (strength >= 90) return 5;
    if (strength >= 70) return 4;
    if (strength >= 50) return 3;
    if (strength >= 30) return 2;
    if (strength > 0) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final bars = _barsFromStrength(strength);
    final Color activeColor = strength >= 70
        ? Colors.greenAccent
        : (strength >= 40 ? Colors.orangeAccent : Colors.redAccent);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final bool active = i < bars;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: size * 0.3,
            height: size * (0.5 + i * 0.25),
            decoration: BoxDecoration(
              color: active ? activeColor : Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

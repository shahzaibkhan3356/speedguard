import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../Bloc/SpeedLimitBloc/SpeedLimitBloc.dart';

class SpeedLimitWidget extends StatefulWidget {
  const SpeedLimitWidget({super.key});

  @override
  State<SpeedLimitWidget> createState() => _SpeedLimitWidgetState();
}

class _SpeedLimitWidgetState extends State<SpeedLimitWidget> {
  late TextEditingController _controller;
  double _currentLimit = 60.0; // default

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _currentLimit.toInt().toString());
    context.read<SpeedLimitBloc>().add(LoadSpeedLimit());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SpeedLimitBloc, SpeedLimitState>(
      listener: (context, state) {
        if (state is SpeedLimitLoaded) {
          setState(() {
            _currentLimit = state.limitKmh;
            _controller.text = _currentLimit.toInt().toString();
          });
        }
      },
      child: Card(
        color: Colors.black87,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Speed Limit",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "${_currentLimit.toInt()} km/h",
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Set new limit',
                        hintStyle: const TextStyle(color: Colors.white38),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blueAccent),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final double? newLimit =
                      double.tryParse(_controller.text.trim());
                      if (newLimit != null && newLimit > 0) {
                        FocusScope.of(context).unfocus();
                        context
                            .read<SpeedLimitBloc>()
                            .add(UpdateSpeedLimit(newLimit));
                        Fluttertoast.showToast(
                          msg: "Speed Limit Set to ${newLimit.toInt()} km/h",
                          backgroundColor: Colors.orangeAccent,
                          textColor: Colors.black,
                        );
                      } else {
                        Fluttertoast.showToast(
                          msg: "Enter a valid number",
                          backgroundColor: Colors.redAccent,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                    ),
                    child: const Text(
                      "Save",
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

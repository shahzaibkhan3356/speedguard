// import 'package:flutter/material.dart';
// import 'package:flutter_bloc/flutter_bloc.dart';
// import 'package:fluttertoast/fluttertoast.dart';

// import '../../Bloc/SpeedBloc/SpeedBloc.dart';

// class SpeedLimitWidget extends StatefulWidget {
//   const SpeedLimitWidget({super.key});

//   @override
//   State<SpeedLimitWidget> createState() => _SpeedLimitWidgetState();
// }

// class _SpeedLimitWidgetState extends State<SpeedLimitWidget> {
//   late TextEditingController _controller;

//   @override
//   void initState() {
//     super.initState();
//     final speedBloc = context.read<SpeedBloc>();
//     _controller = TextEditingController(
//       text: speedBloc.state.speedLimit.toInt().toString(),
//     );
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return BlocBuilder<SpeedBloc, SpeedState>(
//       builder: (context, state) {
//         final double currentLimit = state.speedLimit;

//         return Card(
//           color: Colors.black87,
//           margin: const EdgeInsets.all(16),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(16),
//           ),
//           child: Padding(
//             padding: const EdgeInsets.all(16),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 const Text(
//                   "Speed Limit",
//                   style: TextStyle(
//                     color: Colors.white70,
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   "${currentLimit.toInt()} ${state.useMph ? "mph" : "km/h"}",
//                   style: const TextStyle(
//                     color: Colors.orangeAccent,
//                     fontSize: 28,
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 const SizedBox(height: 16),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: TextField(
//                         controller: _controller,
//                         keyboardType: TextInputType.number,
//                         style: const TextStyle(color: Colors.white),
//                         decoration: InputDecoration(
//                           hintText: 'Set new limit',
//                           hintStyle: const TextStyle(color: Colors.white38),
//                           enabledBorder: OutlineInputBorder(
//                             borderRadius: BorderRadius.circular(12),
//                             borderSide: const BorderSide(color: Colors.white24),
//                           ),
//                           focusedBorder: OutlineInputBorder(
//                             borderRadius: BorderRadius.circular(12),
//                             borderSide: const BorderSide(
//                               color: Colors.blueAccent,
//                             ),
//                           ),
//                           contentPadding: const EdgeInsets.symmetric(
//                             vertical: 12,
//                             horizontal: 16,
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     ElevatedButton(
//                       onPressed: () {
//                         final double? newLimit = double.tryParse(
//                           _controller.text.trim(),
//                         );

//                         if (newLimit != null && newLimit > 0) {
//                           FocusScope.of(context).unfocus();

//                           // ✅ Dispatch directly to SpeedBloc
//                           context.read<SpeedBloc>().add(
//                             UpdateSpeedLimit(newLimit),
//                           );

//                           Fluttertoast.showToast(
//                             msg:
//                                 "Speed Limit Set to ${newLimit.toInt()} ${state.useMph ? "mph" : "km/h"}",
//                             backgroundColor: Colors.orangeAccent,
//                             textColor: Colors.black,
//                           );
//                         } else {
//                           Fluttertoast.showToast(
//                             msg: "Enter a valid number",
//                             backgroundColor: Colors.redAccent,
//                           );
//                         }
//                       },
//                       style: ElevatedButton.styleFrom(
//                         backgroundColor: Colors.orangeAccent,
//                         shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         padding: const EdgeInsets.symmetric(
//                           vertical: 14,
//                           horizontal: 20,
//                         ),
//                       ),
//                       child: const Text(
//                         "Save",
//                         style: TextStyle(
//                           color: Colors.black87,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

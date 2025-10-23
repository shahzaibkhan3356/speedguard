import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ===== 🎨 COLORS =====
  static const Color primary = Color(0xFF5B5FE9);
  static const Color secondary = Color(0xFF3D3FE3);
  static const Color background = Color(0xFF0E0E12);
  static const Color white = Colors.white;
  static const Color grey = Colors.grey;
  static const Color danger = Color(0xFFFF4C4C);

  // ===== 🧩 BASE FONT STYLE =====
  static TextStyle _base({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color color = white,
  }) {
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  // ===== 🔠 TEXT STYLES =====
  static TextStyle get heading1 => _base(fontSize: 32, fontWeight: FontWeight.bold);
  static TextStyle get heading2 => _base(fontSize: 24, fontWeight: FontWeight.w600);
  static TextStyle get title => _base(fontSize: 18, fontWeight: FontWeight.w500);
  static TextStyle get body => _base(fontSize: 14, fontWeight: FontWeight.normal);
  static TextStyle get small => _base(fontSize: 12, fontWeight: FontWeight.w400);
  static TextStyle get label => _base(fontSize: 10, fontWeight: FontWeight.w500, color: grey);

  // ===== 🌙 THEME DATA =====
  static ThemeData get darkTheme => ThemeData(
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: background,
    ),
    textTheme: TextTheme(
      displayLarge: heading1,
      displayMedium: heading2,
      titleLarge: title,
      bodyLarge: body,
      bodyMedium: small,
      labelLarge: label,
    ),
    useMaterial3: true,
  );
}

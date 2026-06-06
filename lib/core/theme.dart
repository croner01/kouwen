import 'package:flutter/material.dart';

const _primaryColor = Color(0xFF4F46E5);
const _surfaceLight = Color(0xFFF8FAFC);
const _surfaceDark = Color(0xFF0F172A);
const _textLight = Color(0xFF1E293B);
const _textDark = Color(0xFFE2E8F0);
const _subtitleLight = Color(0xFF64748B);
const _subtitleDark = Color(0xFF94A3B8);

final lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _primaryColor,
    brightness: Brightness.light,
    surface: _surfaceLight,
  ),
  scaffoldBackgroundColor: _surfaceLight,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: _textLight,
    elevation: 0,
    scrolledUnderElevation: 1,
    centerTitle: false,
    titleTextStyle: TextStyle(
        color: _textLight, fontSize: 18, fontWeight: FontWeight.w600),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: _primaryColor, width: 1.5),
    ),
    hintStyle: const TextStyle(color: _subtitleLight, fontSize: 15),
  ),
  iconTheme: const IconThemeData(color: _subtitleLight, size: 22),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: _primaryColor,
    unselectedItemColor: _subtitleLight,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
  dividerTheme:
      DividerThemeData(color: Colors.grey.shade200, thickness: 1, space: 1),
);

final darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _primaryColor,
    brightness: Brightness.dark,
    surface: _surfaceDark,
  ),
  scaffoldBackgroundColor: _surfaceDark,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1E293B),
    foregroundColor: _textDark,
    elevation: 0,
    scrolledUnderElevation: 1,
    centerTitle: false,
    titleTextStyle: TextStyle(
        color: _textDark, fontSize: 18, fontWeight: FontWeight.w600),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF1E293B),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.grey.shade800),
    ),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF1E293B),
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: Colors.grey.shade700),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: Colors.grey.shade700),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: const BorderSide(color: _primaryColor, width: 1.5),
    ),
    hintStyle: const TextStyle(color: _subtitleDark, fontSize: 15),
  ),
  iconTheme: const IconThemeData(color: _subtitleDark, size: 22),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Color(0xFF1E293B),
    selectedItemColor: _primaryColor,
    unselectedItemColor: _subtitleDark,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
  dividerTheme:
      DividerThemeData(color: Colors.grey.shade800, thickness: 1, space: 1),
);

import 'package:flutter/material.dart';

abstract final class KColors {
  static const background = Color(0xFF070B1A);
  static const surface = Color(0xFF111832);
  static const surfaceHigh = Color(0xFF1A2347);
  static const cyan = Color(0xFF4FD1FF);
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const green = Color(0xFF34D399);
  static const textDim = Color(0xFF8A93B8);

  static const accentGradient = LinearGradient(
    colors: [cyan, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Stable avatar gradient for a device id.
  static LinearGradient avatarGradient(String id) {
    final seed = int.tryParse(id.length >= 6 ? id.substring(0, 6) : id, radix: 16) ?? 0;
    final hue = (seed % 360).toDouble();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1, hue, 0.75, 0.62).toColor(),
        HSLColor.fromAHSL(1, (hue + 40) % 360, 0.7, 0.45).toColor(),
      ],
    );
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: KColors.violet,
    brightness: Brightness.dark,
  ).copyWith(
    primary: KColors.cyan,
    secondary: KColors.violet,
    surface: KColors.surface,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: KColors.background,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: KColors.background,
      elevation: 0,
      centerTitle: false,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: KColors.surface,
      showDragHandle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: KColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

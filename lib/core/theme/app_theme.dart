import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0E0F12);
  static const surface = Color(0xFF1A1C21);
  static const elevated = Color(0xFF242730);
  static const primary = Color(0xFFFF5A1F);
  static const primaryDim = Color(0xFF7A2E16);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFF5F6F8);
  static const textSecondary = Color(0xFF9BA1AD);
  static const textMuted = Color(0xFF5A5F6B);
  static const divider = Color(0xFF2A2D35);
}

/// Editorial / "athletic poster" style display typography. Used for the
/// exercise hero title and other hero numerals. Built from the system font
/// with extreme weight + tracking to feel custom without a font asset.
class AppDisplay {
  static const TextStyle hero = TextStyle(
    fontSize: 44,
    height: 0.95,
    fontWeight: FontWeight.w900,
    letterSpacing: -1.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle megaNumber = TextStyle(
    fontSize: 64,
    height: 0.9,
    fontWeight: FontWeight.w900,
    letterSpacing: -2,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle eyebrow = TextStyle(
    fontSize: 11,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 2.0,
    color: AppColors.textSecondary,
  );

  static const TextStyle stat = TextStyle(
    fontSize: 22,
    height: 1.0,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const TextStyle mono = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: AppColors.textSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        error: AppColors.danger,
        onError: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      dividerColor: AppColors.divider,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(
          fontSize: 48,
          height: 56 / 48,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.2,
        ),
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontSize: 28,
          height: 34 / 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 22,
          height: 28 / 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          fontSize: 17,
          height: 24 / 17,
        ),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontSize: 11,
          height: 16 / 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.elevated,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider, width: 1),
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppColors.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(color: AppColors.textSecondary),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: AppColors.surface,
        iconColor: AppColors.textSecondary,
      ),
    );
  }
}

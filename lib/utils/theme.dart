import 'package:flutter/material.dart';

/// Google-inspired palette — red, blue, green and yellow accents
/// on clean light surfaces.
class AppColors {
  // Google palette
  static const Color googleRed = Color(0xFFEA4335);
  static const Color googleBlue = Color(0xFF4285F4);
  static const Color googleGreen = Color(0xFF34A853);
  static const Color googleYellow = Color(0xFFFBBC05);
  static const Color googleYellowDark = Color(0xFFF9AB00); // readable on white

  // Neutrals
  static const Color white = Colors.white;
  static const Color darkText = Color(0xFF202124);
  static const Color background = Color(0xFFFAFAFA);
  static const Color border = Color(0xFFDADCE0);
  static const Color greyText = Color(0xFF5F6368);
  static const Color lightGrey = Color(0xFFF1F3F4);
  static const Color avatarBg = Color(0xFFE8F0FE); // Google light-blue tint

  // Semantic status colors
  static const Color stable = googleGreen;
  static const Color caution = googleRed;
  static const Color info = googleBlue;
  static const Color warning = googleYellowDark;
}

class AppTheme {
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.googleBlue)
          .copyWith(
            primary: AppColors.googleBlue,
            secondary: AppColors.googleGreen,
            tertiary: AppColors.googleYellow,
            error: AppColors.googleRed,
            surface: AppColors.white,
            onSurface: AppColors.darkText,
            outline: AppColors.border,
          ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.darkText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.darkText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        labelStyle: const TextStyle(
          color: AppColors.darkText,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1,
        ),
        hintStyle: const TextStyle(color: AppColors.greyText, fontSize: 14),
        prefixIconColor: AppColors.googleBlue,
        suffixIconColor: AppColors.greyText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.googleBlue, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.googleBlue,
          foregroundColor: AppColors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.googleBlue,
          side: const BorderSide(color: AppColors.googleBlue, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.googleBlue,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        side: const BorderSide(color: AppColors.greyText),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.googleBlue
              : null,
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.googleBlue,
        side: BorderSide(color: AppColors.border),
        labelStyle: TextStyle(
          color: AppColors.darkText,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.googleBlue,
        unselectedItemColor: AppColors.greyText,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.googleBlue),
    );
  }
}

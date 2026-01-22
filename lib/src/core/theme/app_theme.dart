import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Premium Color Palette - Enhanced
  static const Color primaryColor = Color(0xFF8B5CF6); // Violet-500 (More vibrant)
  static const Color primaryVariant = Color(0xFF7C3AED); // Violet-600
  static const Color secondaryColor = Color(0xFF10B981); // Emerald-500
  static const Color secondaryVariant = Color(0xFF059669); // Emerald-600
  
  static const Color backgroundColor = Color(0xFF0F172A); // Slate-900 (Rich Dark Blue)
  static const Color surfaceColor = Color(0xFF1E293B); // Slate-800
  static const Color surfaceColorLight = Color(0xFF334155); // Slate-700
  
  static const Color errorColor = Color(0xFFEF4444); // Red-500
  static const Color onPrimary = Colors.white;
  static const Color onBackground = Color(0xFFF1F5F9); // Slate-100
  static const Color onSurface = Color(0xFFE2E8F0); // Slate-200
  static const Color textSecondary = Color(0xFF94A3B8); // Slate-400

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, primaryVariant],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [surfaceColor, surfaceColorLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        secondary: secondaryColor,
      ),
      textTheme: GoogleFonts.outfitTextTheme(),
      inputDecorationTheme: _inputDecorationTheme(Brightness.light),
      elevatedButtonTheme: _elevatedButtonThemeData,
      cardTheme: _cardTheme,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        error: errorColor,
        onPrimary: onPrimary,
        onSurface: onSurface,
        background: backgroundColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent, // Glass effect readiness
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: _inputDecorationTheme(Brightness.dark),
      elevatedButtonTheme: _elevatedButtonThemeData,
      cardTheme: _cardTheme,
      
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: onBackground,
        ),
        headlineMedium: GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: onBackground,
        ),
        titleMedium: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: onBackground,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 16,
          color: onSurface,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 14,
          color: textSecondary,
        ),
      ),
    );
  }

  // Shared Component Themes
  
  static InputDecorationTheme _inputDecorationTheme(Brightness brightness) {
    final borderColor = brightness == Brightness.dark ? surfaceColorLight : Colors.grey.shade300;
    final fillColor = brightness == Brightness.dark ? surfaceColor.withValues(alpha: 0.5) : Colors.grey.shade50;
    
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: errorColor),
      ),
      prefixIconColor: textSecondary,
      labelStyle: TextStyle(color: textSecondary),
    );
  }

  static ElevatedButtonThemeData get _elevatedButtonThemeData {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        shadowColor: primaryColor.withValues(alpha: 0.4),
        textStyle: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static CardThemeData get _cardTheme {
    return CardThemeData(
      color: surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24), 
        side: const BorderSide(color: surfaceColorLight, width: 1),
      ),
      margin: EdgeInsets.zero,
    );
  }
}

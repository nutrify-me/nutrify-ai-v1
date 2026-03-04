import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Vibrant & Warm design system — Strava/Fitbit-inspired
class AppTheme {
  // ─── Brand Colors ────────────────────────────────────
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color secondary = Color(0xFF10B981);
  static const Color tertiary = Color(0xFF8B5CF6);
  static const Color accent = Color(0xFFFF6B35);

  // ─── Semantic Colors ─────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── Metric Colors (consistent across app) ──────────
  static const Color calorieColor = Color(0xFFFF6B35);
  static const Color proteinColor = Color(0xFFEF4444);
  static const Color carbsColor = Color(0xFFF59E0B);
  static const Color fatColor = Color(0xFF8B5CF6);
  static const Color waterColor = Color(0xFF0EA5E9);
  static const Color stepsColor = Color(0xFF10B981);
  static const Color heartColor = Color(0xFFEC4899);
  static const Color sleepColor = Color(0xFF6366F1);
  static const Color weightColor = Color(0xFF14B8A6);

  // ─── Gradient Pairs ──────────────────────────────────
  static const calorieGradient = [Color(0xFFFF6B35), Color(0xFFFF8C42)];
  static const proteinGradient = [Color(0xFFEF4444), Color(0xFFF87171)];
  static const fitnessGradient = [Color(0xFF6366F1), Color(0xFF818CF8)];
  static const waterGradient = [Color(0xFF0EA5E9), Color(0xFF38BDF8)];
  static const successGradient = [Color(0xFF10B981), Color(0xFF34D399)];
  static const heroGradient = [Color(0xFF1E3A5F), Color(0xFF2563EB)];
  static const runGradient = [Color(0xFF059669), Color(0xFF10B981)];
  static const darkGradient = [Color(0xFF0F172A), Color(0xFF1E293B)];

  // ─── Light Theme ─────────────────────────────────────

  static const Color _lightBg = Color(0xFFF0F2F5);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceVariant = Color(0xFFF7F8FA);
  static const Color _lightText = Color(0xFF111827);
  static const Color _lightTextSecondary = Color(0xFF6B7280);

  // Keep old names working for existing code
  static const Color background = _lightBg;
  static const Color surface = _lightSurface;
  static const Color surfaceContainerHighest = _lightSurfaceVariant;
  static const Color onSurface = _lightText;
  static const Color onSurfaceVariant = _lightTextSecondary;

  static ThemeData get lightTheme {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: secondary,
        tertiary: tertiary,
        surface: _lightSurface,
        onSurface: _lightText,
        onSurfaceVariant: _lightTextSecondary,
        surfaceContainerHighest: _lightSurfaceVariant,
        error: error,
      ),
      scaffoldBackgroundColor: _lightBg,
      textTheme: _buildTextTheme(base.textTheme, _lightText, _lightTextSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: _lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: _lightText,
        ),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFFE5E7EB).withAlpha(120)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: primary.withAlpha(80)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: _lightTextSecondary),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: _lightTextSecondary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _lightSurface,
        selectedItemColor: primary,
        unselectedItemColor: _lightTextSecondary,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        indicatorColor: primary.withAlpha(25),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: primary);
          }
          return GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: _lightTextSecondary);
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _lightSurfaceVariant,
        selectedColor: primary.withAlpha(25),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: _lightText),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1F2937),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
        actionTextColor: secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      dividerTheme: DividerThemeData(
        color: const Color(0xFFE5E7EB).withAlpha(80),
        thickness: 1,
      ),
    );
  }

  // ─── Dark Theme ──────────────────────────────────────

  static const Color _darkBg = Color(0xFF0F172A);
  static const Color _darkSurface = Color(0xFF1E293B);
  static const Color _darkSurfaceVariant = Color(0xFF334155);
  static const Color _darkText = Color(0xFFF1F5F9);
  static const Color _darkTextSecondary = Color(0xFF94A3B8);

  static ThemeData get darkTheme {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF60A5FA),
        onPrimary: Color(0xFF0F172A),
        secondary: Color(0xFF34D399),
        tertiary: Color(0xFFA78BFA),
        surface: _darkSurface,
        onSurface: _darkText,
        onSurfaceVariant: _darkTextSecondary,
        surfaceContainerHighest: _darkSurfaceVariant,
        error: Color(0xFFFCA5A5),
      ),
      scaffoldBackgroundColor: _darkBg,
      textTheme: _buildTextTheme(base.textTheme, _darkText, _darkTextSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: _darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: _darkText,
        ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF475569).withAlpha(80)),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF60A5FA),
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF60A5FA),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: const Color(0xFF60A5FA).withAlpha(80)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF60A5FA),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: _darkTextSecondary),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: _darkTextSecondary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _darkSurface,
        selectedItemColor: const Color(0xFF60A5FA),
        unselectedItemColor: _darkTextSecondary,
        selectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurface,
        indicatorColor: const Color(0xFF60A5FA).withAlpha(40),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _darkSurfaceVariant,
        selectedColor: const Color(0xFF60A5FA).withAlpha(40),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: _darkText),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF334155),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: _darkText),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF475569).withAlpha(60),
        thickness: 1,
      ),
    );
  }

  // ─── Typography Builder ──────────────────────────────

  static TextTheme _buildTextTheme(TextTheme base, Color primary, Color secondary) {
    return GoogleFonts.interTextTheme(base).copyWith(
      displayLarge: GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: -1.5, color: primary),
      displayMedium: GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1, color: primary),
      displaySmall: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: primary),
      headlineMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: primary),
      headlineSmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700, color: primary),
      titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
      titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
      titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: primary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: secondary),
      bodySmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: secondary),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: secondary),
      labelSmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: secondary),
    );
  }

  // ─── Helper Decorations ──────────────────────────────

  /// Card with subtle colored tint (for metric tiles)
  static BoxDecoration tintedCard(Color color, {bool isDark = false}) {
    return BoxDecoration(
      color: isDark ? color.withAlpha(25) : color.withAlpha(12),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withAlpha(isDark ? 40 : 30)),
    );
  }

  /// Card with left-accent border (for meal/exercise cards)
  static BoxDecoration accentCard(Color color, {Color? bg}) {
    return BoxDecoration(
      color: bg ?? color.withAlpha(8),
      borderRadius: BorderRadius.circular(12),
      border: Border(left: BorderSide(color: color, width: 4)),
    );
  }

  /// Gradient header
  static BoxDecoration gradientHeader(List<Color> colors) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    );
  }

  /// Metric pill badge
  static Widget metricPill(String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, color: color, fontSize: 14)),
          const SizedBox(width: 2),
          Text(unit,
              style: GoogleFonts.inter(color: color.withAlpha(180), fontSize: 11)),
        ],
      ),
    );
  }
}

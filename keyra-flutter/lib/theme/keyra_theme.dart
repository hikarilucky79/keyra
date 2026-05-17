library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KeyraTheme {
  KeyraTheme._();

  // ── Catppuccin Mocha Palette ──────────────────────────────────────
  // No blue tones as requested.

  static const Color base = Color(0xFF1E1E2E);
  static const Color mantle = Color(0xFF181825);
  static const Color crust = Color(0xFF11111B);
  
  static const Color surface0 = Color(0xFF313244);
  static const Color surface1 = Color(0xFF45475A);
  static const Color surface2 = Color(0xFF585B70);

  static const Color text = Color(0xFFCDD6F4);
  static const Color subtext1 = Color(0xFFBAC2DE);
  static const Color subtext0 = Color(0xFFA6ADC8);
  static const Color overlay2 = Color(0xFF9399B2);
  static const Color overlay1 = Color(0xFF7F849C);
  static const Color overlay0 = Color(0xFF6C7086);

  static const Color mauve = Color(0xFFCBA6F7);
  static const Color lavender = Color(0xFFB4BEFE);
  static const Color pink = Color(0xFFF5C2E7);
  static const Color peach = Color(0xFFFAB387);
  static const Color yellow = Color(0xFFF9E2AF);
  static const Color green = Color(0xFFA6E3A1);
  static const Color red = Color(0xFFF38BA8);
  static const Color flamingo = Color(0xFFF2CDCD);

  // ── Theme Aliases ────────────────────────────────────────────────
  
  static const Color background = base;
  static const Color surface = surface0;
  static const Color surfaceVariant = mantle;
  static const Color card = mantle;
  static const Color cardHover = surface0;

  static const Color border = surface1;
  static const Color borderSubtle = surface0;

  static const Color foreground = text;
  static const Color foregroundMuted = subtext0;
  static const Color foregroundSubtle = overlay0;

  // Primary (Mauve - macOS feel)
  static const Color primary = mauve;
  static const Color primaryMuted = Color(0x33CBA6F7);

  // Status colors
  static const Color success = green;
  static const Color successMuted = Color(0x26A6E3A1);
  static const Color warning = yellow;
  static const Color error = red;

  // ── Gradients & Shadows ─────────────────────────────────────────

  static const LinearGradient accentGradient = LinearGradient(
    colors: [mauve, pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [base, mantle],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static List<BoxShadow> get macShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 15,
          offset: const Offset(0, 8),
          spreadRadius: -2,
        ),
      ];

  static List<BoxShadow> get glowShadow => [
        BoxShadow(
          color: mauve.withValues(alpha: 0.15),
          blurRadius: 20,
          spreadRadius: -4,
        ),
      ];

  // ── Border Radius (macOS style - rounded) ───────────────────────

  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
  static const double radiusXl = 18;

  // ── ThemeData ─────────────────────────────────────────────────

  static ThemeData get dark {
    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: foreground,
      displayColor: foreground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: pink,
        surface: surface,
        error: error,
        onPrimary: Color(0xFF000000),
        onSecondary: Color(0xFF000000),
        onSurface: foreground,
        onError: Color(0xFF000000),
        outline: border,
        outlineVariant: borderSubtle,
      ),
      textTheme: textTheme,
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: border.withValues(alpha: 0.5)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: surface1,
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: mantle.withValues(alpha: 0.8),
        indicatorColor: primaryMuted,
        labelTextStyle: WidgetStateProperty.all(
          textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: text,
          ),
        ),
      ),
      iconTheme: const IconThemeData(
        color: subtext0,
        size: 18,
      ),
    );
  }

  // ── Text Styles ───────────────────────────────────────────────

  static TextStyle get h1 => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: text,
        letterSpacing: -0.5,
      );

  static TextStyle get h2 => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: -0.2,
      );

  static TextStyle get h3 => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: text,
      );

  static TextStyle get bodyMuted => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: subtext0,
      );
}

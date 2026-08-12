import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFFFF6B2B);
  static const Color primaryDark = Color(0xFFE55A1F);
  static const Color lime = Color(0xFFBAFF29);
  static const Color bg = Color(0xFF0C0C0C);
  static const Color surface = Color(0xFF111111);
  static const Color surface2 = Color(0xFF1A1A1A);
  static const Color textPrimary = Color(0xFFF5F5F0);
  static const Color textSecondary = Color(0x8CF5F5F0);
  static const Color divider = Color(0x14FFFFFF);

  // Brand secondary palette — used by the dark Trip Builder feature (and
  // reserved for future surfaces). Distinct from Profile's local light `_k*`
  // consts: these are the DARK colorway, never substitute one set for the other.
  static const Color primaryLight = Color(0xFFFF9166);
  static const Color primarySoft = Color(0x1FFF6B2B); // primary @ 12%
  static const Color teal = Color(0xFF5DCAA5);
  static const Color purple = Color(0xFFAFA9EC);
  static const Color pink = Color(0xFFED93B1);

  // Budget-feedback states (Trip Builder progress/total thresholds).
  static const Color warn = Color(0xFFFAC775);
  static const Color danger = Color(0xFFE24B4A);

  /// Opacity of the bottom-nav "warm pill" behind the selected item — orange
  /// (`primary`) laid over the near-black bar at 16%. Single source of truth so
  /// the pill tint stays in lockstep with the brand colour.
  static const double navPillOpacity = 0.16;

  // Light-sheet sub-palette — the discovery feed renders on a white sheet that
  // sits over the dark map, so it needs its own ink/surface tokens rather than
  // the dark-theme greys. Named here so the sheet/cards stop hardcoding hex.
  static const Color sheetSurface = Color(0xFFFFFFFF);
  static const Color sheetInk = Color(0xFF111111);
  static const Color sheetSubInk = Color(0xFF8A8A8A);
  static const Color sheetBorder = Color(0xFFEDEDED);
  static const Color sheetChipIdle = Color(0xFFF2F2F2);
  static const Color sheetChipBorder = Color(0xFFE2E2E2);
  static const Color sheetHandle = Color(0xFFD9D9D9);

  // Warm light palette — the unified theme for the whole trip-planner journey
  // (Profile, My Trip, trip creation/edit, Trip Builder, bottom nav). Single
  // source of truth: previously duplicated as Profile's private `_k*` consts
  // and trip_setup's `kSetup*` consts; both now point here. Distinct from the
  // `sheet*` tokens above (a cooler neutral gray built for the map's discovery
  // sheet, unrelated purpose) — don't conflate the two palettes.
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFF5F3EF);
  static const Color lightBorder = Color(0xFFE7E2D9);
  static const Color lightInk = Color(0xFF1A1A1A);
  static const Color lightMute = Color(0xFF8A8A8A);

  static TextTheme get _textTheme => GoogleFonts.dmSansTextTheme(
        const TextTheme(
          displayLarge: TextStyle(color: textPrimary),
          displayMedium: TextStyle(color: textPrimary),
          displaySmall: TextStyle(color: textPrimary),
          headlineLarge: TextStyle(color: textPrimary),
          headlineMedium: TextStyle(color: textPrimary),
          headlineSmall: TextStyle(color: textPrimary),
          titleLarge: TextStyle(color: textPrimary),
          titleMedium: TextStyle(color: textPrimary),
          titleSmall: TextStyle(color: textPrimary),
          bodyLarge: TextStyle(color: textPrimary),
          bodyMedium: TextStyle(color: textPrimary),
          bodySmall: TextStyle(color: textSecondary),
          labelLarge: TextStyle(color: textPrimary),
          labelMedium: TextStyle(color: textSecondary),
          labelSmall: TextStyle(color: textSecondary),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: primary,
          surface: surface,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: textPrimary,
        ),
        scaffoldBackgroundColor: bg,
        textTheme: _textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          hintStyle: const TextStyle(color: textSecondary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: divider),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: bg,
          indicatorColor: primary.withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600, color: primary);
            }
            return GoogleFonts.dmSans(fontSize: 10, color: textSecondary);
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: primary);
            }
            return const IconThemeData(color: textSecondary);
          }),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bg,
          selectedItemColor: primary,
          unselectedItemColor: textSecondary,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: surface2,
          selectedColor: primary,
          labelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600),
          side: const BorderSide(color: divider),
          shape: const StadiumBorder(),
        ),
      );

  // Keep light theme alias pointing to dark for now
  static ThemeData get lightTheme => darkTheme;
}

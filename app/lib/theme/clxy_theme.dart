import 'package:flutter/material.dart';
import 'clxy_colors.dart';

const LinearGradient clxyBrandGradient = LinearGradient(
  colors: [ClxyColors.cyanBright, Color(0xFF60A5FA), ClxyColors.pinkAccent],
);

const LinearGradient clxyPrimaryButtonBrush = LinearGradient(
  colors: [ClxyColors.cyanGlow, ClxyColors.bluePrimary, ClxyColors.purplePrimary],
);

const LinearGradient clxyDisconnectBrush = LinearGradient(
  colors: [ClxyColors.redDisconnectStart, ClxyColors.redDisconnectEnd],
);

ThemeData buildClxyTheme({bool isRtl = false}) {
  final fontFamily = isRtl ? 'Vazirmatn' : 'Inter';
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: ClxyColors.bgTop,
    fontFamily: fontFamily,
    colorScheme: const ColorScheme.dark(
      primary: ClxyColors.cyanGlow,
      onPrimary: ClxyColors.bgTop,
      primaryContainer: ClxyColors.blueDeep,
      onPrimaryContainer: ClxyColors.textPrimary,
      secondary: ClxyColors.bluePrimary,
      onSecondary: ClxyColors.textPrimary,
      surface: ClxyColors.cardSurfaceSolid,
      onSurface: ClxyColors.textPrimary,
      error: ClxyColors.redDisconnectStart,
      onError: ClxyColors.textPrimary,
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(fontFamily: fontFamily, fontSize: 44, height: 48 / 44, letterSpacing: 0.5),
      headlineSmall: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.bold, fontSize: 20, height: 26 / 20, letterSpacing: -0.3),
      titleLarge: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 18, height: 24 / 18, letterSpacing: -0.2),
      titleMedium: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 14, height: 20 / 14),
      bodyLarge: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.normal, fontSize: 14, height: 20 / 14),
      bodyMedium: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.normal, fontSize: 12.5, height: 19 / 12.5),
      bodySmall: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.normal, fontSize: 11, height: 16 / 11),
      labelMedium: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 11.5, height: 14 / 11.5),
      labelSmall: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w500, fontSize: 10.5, height: 14 / 10.5),
    ),
  );
}

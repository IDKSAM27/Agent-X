import 'package:flutter/material.dart';

class AppConstants {
  // App Information
  static const String appName = 'Agent X';
  static const String appVersion = '1.0.0';
  static const String appDescription = 'Your intelligent personal assistant';

  // Animation Durations
  static const Duration fastAnimation = Duration(milliseconds: 200);
  static const Duration normalAnimation = Duration(milliseconds: 300);
  static const Duration slowAnimation = Duration(milliseconds: 500);

  // Spacing
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  // Border Radius
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 20.0;

  // Padding
  static EdgeInsets get paddingS => const EdgeInsets.all(spacingS);
  static EdgeInsets get paddingM => const EdgeInsets.all(spacingM);
  static EdgeInsets get paddingL => const EdgeInsets.all(spacingL);
  static EdgeInsets get paddingXL => const EdgeInsets.all(spacingXL);

  // Page Padding
  static EdgeInsets get pagePadding => const EdgeInsets.symmetric(
    horizontal: spacingL,
    vertical: spacingM,
  );

  // Card Padding
  static EdgeInsets get cardPadding => const EdgeInsets.all(spacingM);

  // API Configuration
  static const Duration apiTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
}

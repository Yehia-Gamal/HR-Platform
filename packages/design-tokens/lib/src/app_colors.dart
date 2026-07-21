import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand
  static const brandPrimary = Color(0xFF0B4FA2);
  static const brandPrimaryStrong = Color(0xFF073B7A);
  static const accent = Color(0xFF00A8D6);

  // Light theme
  static const lightBackground = Color(0xFFF4F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF10233F);
  static const lightBorder = Color(0xFFDCE5F0);
  static const lightBorderStrong = Color(0xFFC3D2E4);

  // Dark theme
  static const darkBackground = Color(0xFF020611);
  static const darkSurface = Color(0xFF061127);
  static const darkText = Color(0xFFF5F8FF);
  static const darkBorder = Color(0xFF243652);
  static const darkBorderStrong = Color(0xFF365071);

  // Semantic – web tokens
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const info = Color(0xFF8B5CF6);

  // Semantic – mobile status pills
  static const statusSuccess = Color(0xFF0F9F6E);
  static const statusWarning = Color(0xFFD98508);
  static const statusDanger = Color(0xFFDC3D4B);
  static const statusInfo = Color(0xFF008CB3);
  static const statusViolet = Color(0xFF6D56D9);

  // Evening gradient
  static const eveningDark = Color(0xFF171632);
  static const eveningAccent = Color(0xFF51447D);

  // Brand logo inverse
  static const inverseSubtitle = Color(0xFFC9E5FF);
}

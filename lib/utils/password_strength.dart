import 'package:flutter/material.dart';
import 'constants.dart';

enum PasswordStrength { empty, weak, fair, strong }

PasswordStrength measurePasswordStrength(String p) {
  if (p.isEmpty) return PasswordStrength.empty;
  if (p.length < 8) return PasswordStrength.weak;
  final met = [
    p.contains(RegExp(r'[A-Z]')),
    p.contains(RegExp(r'[a-z]')),
    p.contains(RegExp(r'[0-9]')),
    p.contains(RegExp(r'[^A-Za-z0-9]')),
  ].where((b) => b).length;
  if (met >= 3) return PasswordStrength.strong;
  if (met >= 2) return PasswordStrength.fair;
  return PasswordStrength.weak;
}

extension PasswordStrengthX on PasswordStrength {
  Color get color {
    switch (this) {
      case PasswordStrength.weak:   return AppConstants.errorColor;
      case PasswordStrength.fair:   return Colors.orange;
      case PasswordStrength.strong: return AppConstants.successColor;
      case PasswordStrength.empty:  return Colors.transparent;
    }
  }

  String get label {
    switch (this) {
      case PasswordStrength.weak:   return 'Weak';
      case PasswordStrength.fair:   return 'Fair';
      case PasswordStrength.strong: return 'Strong';
      case PasswordStrength.empty:  return '';
    }
  }

  // 0.0–1.0 for LinearProgressIndicator
  double get fraction {
    switch (this) {
      case PasswordStrength.empty:  return 0;
      case PasswordStrength.weak:   return 1 / 3;
      case PasswordStrength.fair:   return 2 / 3;
      case PasswordStrength.strong: return 1;
    }
  }

  // 0–3 filled segments for the 3-bar indicator in RegisterScreen
  int get filledSegments {
    switch (this) {
      case PasswordStrength.empty:  return 0;
      case PasswordStrength.weak:   return 1;
      case PasswordStrength.fair:   return 2;
      case PasswordStrength.strong: return 3;
    }
  }
}

import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = 'SmartSplit';
  static const String appVersion = '1.0.0';

  // Colors
  static const Color primaryColor = Color(0xFF009688);
  static const Color secondaryColor = Color(0xFF4DB6AC);
  static const Color errorColor = Color(0xFFE53935);
  static const Color successColor = Color(0xFF43A047);
  static const Color backgroundColor = Color(0xFFF5F5F5);

  // Text Styles
  static const TextStyle headingStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  static const TextStyle subheadingStyle = TextStyle(
    fontSize: 16,
    color: Colors.black54,
  );

  // Padding
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;

  // Border Radius
  static const double borderRadius = 12.0;

  // Validation
  static final RegExp emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  // Error Messages
  static const String emailRequired = 'Email is required';
  static const String emailInvalid = 'Please enter a valid email';
  static const String passwordRequired = 'Password is required';
  static const String passwordTooShort = 'Password must be at least 6 characters';
  static const String nameRequired = 'Name is required';
  static const String passwordsDoNotMatch = 'Passwords do not match';
}
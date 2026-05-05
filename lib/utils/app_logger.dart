import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class AppLogger {
  static void error(String context, Object error, [StackTrace? stack]) {
    debugPrint('[$context] $error');
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: context,
      fatal: false,
    );
  }
}

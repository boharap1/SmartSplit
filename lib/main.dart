import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/group_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth/biometric_lock_screen.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_navigation.dart';
import 'utils/app_theme.dart';
import 'utils/constants.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage _) async {}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  final settings = SettingsProvider();
  await settings.initialize();

  runApp(MyApp(settings: settings));
}

class MyApp extends StatefulWidget {
  final SettingsProvider settings;
  const MyApp({super.key, required this.settings});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const AuthWrapper(),
        ),
      ),
    );
  }
}

/// Routes the user to the correct screen based on auth + verification state.
///
/// Decision tree:
///   loading / initial         → splash
///   unauthenticated / error   → LoginScreen
///   authenticated
///     └─ email not verified   → EmailVerificationScreen
///     └─ biometric locked     → BiometricLockScreen
///     └─ all clear            → MainNavigation
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        // ── Splash / loading ───────────────────────────────────────────────
        if (auth.status == AuthStatus.initial ||
            auth.status == AuthStatus.loading) {
          return _SplashScreen();
        }

        // ── Not signed in ──────────────────────────────────────────────────
        if (!auth.isAuthenticated) return const LoginScreen();

        // ── Signed in: email gate ──────────────────────────────────────────
        if (!auth.isEmailVerified) return const EmailVerificationScreen();

        // ── Signed in + verified: biometric gate ───────────────────────────
        if (auth.biometricEnabled && !auth.biometricUnlocked) {
          return const BiometricLockScreen();
        }

        // ── All clear ──────────────────────────────────────────────────────
        return const MainNavigation();
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 80,
              color: AppConstants.primaryColor,
            ),
            const SizedBox(height: 24),
            Text(
              AppConstants.appName,
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: AppConstants.primaryColor),
          ],
        ),
      ),
    );
  }
}

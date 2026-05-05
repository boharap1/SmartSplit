import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../utils/constants.dart';

/// Shown on cold start when the user has biometric lock enabled.
/// Firebase session is already valid at this point — this is purely
/// an app-lock layer. On success, AuthProvider.unlockBiometric() is
/// called and AuthWrapper transitions to MainNavigation automatically.
class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool   _isAuthenticating = false;
  String _error            = '';
  String _primaryLabel     = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadLabel();
    // Trigger automatically on screen open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _loadLabel() async {
    final label = await BiometricService.instance.primaryLabel();
    if (mounted) setState(() => _primaryLabel = label);
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() { _isAuthenticating = true; _error = ''; });

    final result = await BiometricService.instance.authenticate(
      reason: 'Unlock SmartSplit',
    );

    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    switch (result) {
      case BiometricResult.success:
        context.read<AuthProvider>().unlockBiometric();
      case BiometricResult.failure:
        setState(() => _error = 'Authentication failed. Try again.');
      case BiometricResult.notAvailable:
        // Biometric hardware removed or unenrolled — require fresh sign-in
        // rather than silently granting access.
        await context.read<AuthProvider>().signOut();
    }
  }

  Future<void> _signOut() async {
    await context.read<AuthProvider>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthProvider>().user?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Column(
            children: [
              const Spacer(),

              // Lock icon
              Container(
                width: 100,
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  size: 52,
                  color: AppConstants.primaryColor,
                ),
              ),
              const SizedBox(height: 32),

              const Text(
                'Welcome Back',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),

              if (email.isNotEmpty)
                Text(
                  email,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),

              Text(
                'Verify with $_primaryLabel to continue',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
                textAlign: TextAlign.center,
              ),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppConstants.errorColor.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(AppConstants.borderRadius),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppConstants.errorColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error,
                          style:
                              const TextStyle(color: AppConstants.errorColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // Biometric button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAuthenticating ? null : _authenticate,
                  icon: _isAuthenticating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fingerprint_rounded, size: 24),
                  label: Text(
                    _isAuthenticating
                        ? 'Verifying...'
                        : 'Unlock with $_primaryLabel',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              TextButton(
                onPressed: _signOut,
                child: Text(
                  'Sign in with a different account',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

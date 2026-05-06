import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/password_strength.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

/// Shown after the user has verified their email during registration.
/// Collects and confirms a password, then creates the Firebase Auth account.
class PasswordSetupScreen extends StatefulWidget {
  final String name;
  final String email;

  const PasswordSetupScreen({
    super.key,
    required this.name,
    required this.email,
  });

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _obscureNew     = true;
  bool _obscureConfirm = true;
  bool _isSubmitting   = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final success = await context.read<AuthProvider>().registerWithVerifiedEmail(
          name:     widget.name,
          email:    widget.email,
          password: _passwordCtrl.text,
        );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!success) {
      final err = context.read<AuthProvider>().errorMessage ?? 'Account creation failed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppConstants.errorColor),
      );
      return;
    }

    // AuthWrapper has rebuilt with MainNavigation at the root route.
    // Pop every pushed screen (OTP, PasswordSetup) so that root becomes visible.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final newVal = _passwordCtrl.text;
    final s      = measurePasswordStrength(newVal);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),

                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      size: 44, color: AppConstants.primaryColor),
                ),
                const SizedBox(height: 28),

                const Text('Create Your Password',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),

                Text('Almost done, ${widget.name.split(' ').first}!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 36),

                // New password
                CustomTextField(
                  controller: _passwordCtrl,
                  label: 'Password',
                  hint: 'At least 8 characters',
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: _obscureNew,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a password';
                    if (v.length < 8) return 'Password must be at least 8 characters';
                    return null;
                  },
                ),

                if (newVal.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: s.fraction,
                            minHeight: 5,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation(s.color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(s.label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: s.color)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                // Confirm password
                CustomTextField(
                  controller: _confirmCtrl,
                  label: 'Confirm Password',
                  hint: 'Re-enter your password',
                  prefixIcon: Icons.check_circle_outline_rounded,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please confirm your password';
                    if (v != _passwordCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                CustomButton(
                  text: 'Create Account',
                  onPressed: _submit,
                  isLoading: _isSubmitting,
                  icon: Icons.person_add_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

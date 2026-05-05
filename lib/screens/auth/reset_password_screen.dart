import 'package:flutter/material.dart';
import '../../services/otp_service.dart';
import '../../utils/constants.dart';
import '../../utils/password_strength.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

/// Shown after the user has entered their OTP for password reset.
/// Submits (email, otp, newPassword) together to verifyPasswordResetOtp,
/// so the OTP is only consumed once at the final step.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String otp;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    required this.otp,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _passwordCtrl   = TextEditingController();
  final _confirmCtrl    = TextEditingController();
  bool  _obscureNew     = true;
  bool  _obscureConfirm = true;
  bool  _isSubmitting   = false;
  bool  _success        = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final result = await OtpService.instance.verifyPasswordResetOtp(
      email:       widget.email,
      otp:         widget.otp,
      newPassword: _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.success) {
      setState(() => _success = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to reset password.'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _success
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black87),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: _success ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppConstants.successColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            size: 48,
            color: AppConstants.successColor,
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Password Updated!',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'Your password has been reset successfully.\nYou can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], height: 1.6),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // Pop back all the way to LoginScreen.
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Go to Sign In',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // ── Form state ────────────────────────────────────────────────────────────

  Widget _buildForm() {
    final newVal = _passwordCtrl.text;
    final s      = measurePasswordStrength(newVal);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),

          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              size: 44,
              color: AppConstants.primaryColor,
            ),
          ),
          const SizedBox(height: 28),

          const Text(
            'Set New Password',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Choose a strong password for ${widget.email}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 36),

          // New password field
          CustomTextField(
            controller: _passwordCtrl,
            label: 'New Password',
            hint: 'At least 8 characters',
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscureNew,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureNew ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter a new password';
              if (v.length < 8) return 'Password must be at least 8 characters';
              return null;
            },
          ),

          // Strength bar
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
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: s.color,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // Confirm password field
          CustomTextField(
            controller: _confirmCtrl,
            label: 'Confirm Password',
            hint: 'Re-enter your new password',
            prefixIcon: Icons.check_circle_outline_rounded,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password';
              if (v != _passwordCtrl.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 32),

          CustomButton(
            text: 'Reset Password',
            onPressed: _submit,
            isLoading: _isSubmitting,
            icon: Icons.lock_open_rounded,
          ),
        ],
      ),
    );
  }
}

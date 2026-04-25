import 'package:flutter/material.dart';
import '../../services/otp_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import 'otp_verification_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? prefillEmail;

  const ForgotPasswordScreen({super.key, this.prefillEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool    _isSending = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) {
      _emailCtrl.text = widget.prefillEmail!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSending) return;
    setState(() { _isSending = true; _errorMsg = null; });

    final email  = _emailCtrl.text.trim();
    final result = await OtpService.instance.requestPasswordResetOtp(email);

    if (!mounted) return;
    setState(() => _isSending = false);

    if (result.success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email:   email,
            purpose: OtpPurpose.passwordReset,
          ),
        ),
      );
    } else {
      setState(() =>
          _errorMsg = result.error ?? 'Failed to send code. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 20),

                Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_reset_rounded,
                    size: 40,
                    color: AppConstants.primaryColor,
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  'Forgot Password?',
                  style: AppConstants.headingStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter the email linked to your account and we\'ll send a 6-digit reset code.',
                  textAlign: TextAlign.center,
                  style: AppConstants.subheadingStyle,
                ),
                const SizedBox(height: 40),

                CustomTextField(
                  controller: _emailCtrl,
                  label: 'Email Address',
                  hint: 'Enter your email',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return AppConstants.emailRequired;
                    }
                    if (!AppConstants.emailRegex.hasMatch(v.trim())) {
                      return AppConstants.emailInvalid;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                if (_errorMsg != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppConstants.errorColor.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppConstants.borderRadius),
                      border: Border.all(
                        color: AppConstants.errorColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppConstants.errorColor, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMsg!,
                            style: const TextStyle(
                                color: AppConstants.errorColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                CustomButton(
                  text: 'Send Reset Code',
                  onPressed: _isSending ? null : _submit,
                  isLoading: _isSending,
                  icon: Icons.send_rounded,
                ),
                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Back to Sign In',
                      style: TextStyle(color: AppConstants.primaryColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

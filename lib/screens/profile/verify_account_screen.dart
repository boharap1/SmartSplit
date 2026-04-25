import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/otp_service.dart';
import '../../utils/constants.dart';
import '../auth/otp_verification_screen.dart';

class VerifyAccountScreen extends StatefulWidget {
  const VerifyAccountScreen({super.key});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  bool _isSending = false;

  Future<void> _sendVerification() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final email =
        context.read<AuthProvider>().firebaseUser?.email ?? '';
    final result = await OtpService.instance.requestEmailVerificationOtp();

    if (!mounted) return;
    setState(() => _isSending = false);

    if (result.success) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email:   email,
            purpose: OtpPurpose.emailVerification,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to send code. Please try again.'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVerified =
        context.watch<AuthProvider>().isEmailVerified;
    final email = context.watch<AuthProvider>().user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Account'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.largePadding),
        child: isVerified ? _buildVerified() : _buildUnverified(email),
      ),
    );
  }

  Widget _buildVerified() => Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppConstants.successColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_user_rounded,
                size: 64, color: AppConstants.successColor),
          ),
          const SizedBox(height: 24),
          const Text(
            'Account Verified',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'Your email address has been successfully verified. '
            'You have full access to all SmartSplit features.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.successColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_circle_outline,
                      color: AppConstants.successColor, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email Verified',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      SizedBox(height: 2),
                      Text('Your account is fully active',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildUnverified(String email) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB300).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_unread_outlined,
                size: 64, color: Color(0xFFFFB300)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Verify Your Email',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            'We\'ll send a 6-digit code to:',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppConstants.primaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the code in the app to verify your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
          const SizedBox(height: 32),

          // Send code button — navigates to OTP screen on success
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _sendVerification,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _isSending ? 'Sending…' : 'Send Verification Code',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[500],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.borderRadius),
                ),
                elevation: 0,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Tips card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tips',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[500],
                        letterSpacing: 1)),
                const SizedBox(height: 10),
                _tip(Icons.inbox_outlined,
                    'Check your spam or junk folder if you don\'t see the email.'),
                const SizedBox(height: 8),
                _tip(Icons.timer_outlined,
                    'The code expires after 10 minutes. Request a new one if needed.'),
                const SizedBox(height: 8),
                _tip(Icons.dialpad_outlined,
                    'Enter the 6-digit code in the next screen to activate your account.'),
              ],
            ),
          ),
        ],
      );

  Widget _tip(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppConstants.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
        ],
      );
}

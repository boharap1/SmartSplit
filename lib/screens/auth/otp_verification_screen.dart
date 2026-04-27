import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/otp_service.dart';
import '../../utils/constants.dart';
import 'reset_password_screen.dart';

enum OtpPurpose { emailVerification, passwordReset }

class OtpVerificationScreen extends StatefulWidget {
  final String      email;
  final OtpPurpose  purpose;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.purpose,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with WidgetsBindingObserver {
  // ── OTP input ─────────────────────────────────────────────────────────────
  // Single hidden TextField + 6 visual boxes.
  // This approach handles both manual digit-by-digit entry and paste natively.

  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();
  String _otp      = '';
  bool   _isVerifying = false;
  String _errorMsg    = '';

  // ── Resend cooldown ───────────────────────────────────────────────────────
  static const _cooldownSeconds = 60;
  int    _cooldown    = 0;
  bool   _isResending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_onOtpChanged);
    _startCooldown(); // The caller already requested an OTP; start cooldown immediately.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_onOtpChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // Re-request focus when user returns from another app (e.g. email client).
  // Without this, autofocus only fires on first build so the keyboard stays
  // hidden after the user backgrounds the app to check their inbox.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _otp.length < 6 && !_isVerifying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _onOtpChanged() {
    final raw  = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    final clamped = raw.length > 6 ? raw.substring(0, 6) : raw;
    // Only update if the controller text needs sanitising.
    if (_ctrl.text != clamped) {
      _ctrl.value = _ctrl.value.copyWith(
        text:              clamped,
        selection:         TextSelection.collapsed(offset: clamped.length),
        composing:         TextRange.empty,
      );
    }
    setState(() {
      _otp      = clamped;
      _errorMsg = '';
    });
    if (clamped.length == 6) _verify();
  }

  void _startCooldown() {
    _cooldown = _cooldownSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _isResending) return;
    setState(() { _isResending = true; _errorMsg = ''; });

    final result = widget.purpose == OtpPurpose.emailVerification
        ? await OtpService.instance.requestEmailVerificationOtp()
        : await OtpService.instance.requestPasswordResetOtp(widget.email);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.success) {
      _ctrl.clear();
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New code sent. Check your inbox.'),
          backgroundColor: AppConstants.successColor,
        ),
      );
    } else {
      setState(() => _errorMsg = result.error ?? 'Failed to resend code.');
    }
  }

  Future<void> _verify() async {
    if (_otp.length != 6 || _isVerifying) return;
    setState(() { _isVerifying = true; _errorMsg = ''; });
    _focusNode.unfocus();

    if (widget.purpose == OtpPurpose.emailVerification) {
      await _verifyEmailOtp();
    } else {
      await _verifyResetOtp();
    }
  }

  Future<void> _verifyEmailOtp() async {
    final result = await OtpService.instance.verifyEmailOtp(_otp);
    if (!mounted) return;

    if (result.success) {
      // Reload Firebase user so isEmailVerified becomes true.
      await context.read<AuthProvider>().checkEmailVerification();
      // AuthWrapper will route to MainNavigation automatically.
    } else {
      setState(() {
        _isVerifying = false;
        _errorMsg    = result.error ?? 'Verification failed.';
        _ctrl.clear(); // clear boxes on wrong code
      });
    }
  }

  Future<void> _verifyResetOtp() async {
    // We only validate the OTP format here; the actual validation +
    // password update happen together in ResetPasswordScreen.
    // To avoid a double-round-trip, we pass (email, otp) to the next screen
    // and let it call verifyPasswordResetOtp(email, otp, newPassword).
    if (!mounted) return;
    setState(() => _isVerifying = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(
          email: widget.email,
          otp:   _otp,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.purpose == OtpPurpose.emailVerification
        ? 'Verify Your Email'
        : 'Enter Reset Code';
    final subtitle = widget.purpose == OtpPurpose.emailVerification
        ? 'We\'ve sent a 6-digit verification code to'
        : 'We\'ve sent a 6-digit reset code to';

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
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Icon
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.purpose == OtpPurpose.emailVerification
                      ? Icons.mark_email_unread_rounded
                      : Icons.lock_reset_rounded,
                  size: 44,
                  color: AppConstants.primaryColor,
                ),
              ),
              const SizedBox(height: 28),

              Text(
                title,
                style: AppConstants.headingStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 4),
              Text(
                widget.email,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 36),

              // ── OTP boxes ────────────────────────────────────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  // Hidden input collects actual keystrokes and paste.
                  Opacity(
                    opacity: 0,
                    child: SizedBox(
                      height: 1,
                      child: TextField(
                        controller:   _ctrl,
                        focusNode:    _focusNode,
                        autofocus:    true,
                        keyboardType: TextInputType.number,
                        maxLength:    6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ),

                  // Visual boxes tapping either refocuses the hidden field.
                  GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, _buildBox),
                    ),
                  ),
                ],
              ),

              // ── Error ─────────────────────────────────────────────────────
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _errorMsg.isNotEmpty
                    ? Container(
                        key: const ValueKey('err'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppConstants.errorColor
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppConstants.errorColor, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _errorMsg,
                                style: const TextStyle(
                                    color: AppConstants.errorColor,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(key: ValueKey('no-err'), height: 0),
              ),

              const SizedBox(height: 32),

              // ── Verify button (shown while loading) ───────────────────────
              if (_isVerifying)
                Column(
                  children: [
                    const CircularProgressIndicator(
                        color: AppConstants.primaryColor),
                    const SizedBox(height: 12),
                    Text(
                      'Verifying…',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _otp.length == 6 ? _verify : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[200],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      widget.purpose == OtpPurpose.emailVerification
                          ? 'Verify Email'
                          : 'Continue',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // ── Resend ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't get a code? ",
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  _cooldown > 0
                      ? Text(
                          'Resend in ${_cooldown}s',
                          style: TextStyle(
                              color: Colors.grey[400], fontSize: 14),
                        )
                      : GestureDetector(
                          onTap: _isResending ? null : _resend,
                          child: Text(
                            _isResending ? 'Sending…' : 'Resend',
                            style: const TextStyle(
                              color: AppConstants.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single OTP digit box ──────────────────────────────────────────────────

  Widget _buildBox(int i) {
    final filled   = i < _otp.length;
    final isCursor = i == _otp.length && _focusNode.hasFocus;
    final digit    = filled ? _otp[i] : '';
    final hasError = _errorMsg.isNotEmpty;

    final borderColor = hasError
        ? AppConstants.errorColor
        : isCursor
            ? AppConstants.primaryColor
            : filled
                ? AppConstants.primaryColor.withValues(alpha: 0.5)
                : Colors.grey[300]!;

    return Container(
      width: 46,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: filled
            ? AppConstants.primaryColor.withValues(alpha: 0.06)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isCursor ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: filled
          ? Text(
              digit,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: hasError ? AppConstants.errorColor : Colors.black87,
              ),
            )
          : isCursor
              ? Container(
                  width: 2,
                  height: 24,
                  color: AppConstants.primaryColor,
                )
              : null,
    );
  }
}

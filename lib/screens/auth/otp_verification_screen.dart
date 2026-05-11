import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // FilteringTextInputFormatter + SystemChannels
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/otp_service.dart';
import '../../utils/constants.dart';
import 'password_setup_screen.dart';
import 'reset_password_screen.dart';

enum OtpPurpose { registration, emailVerification, passwordReset }

class OtpVerificationScreen extends StatefulWidget {
  final String      email;
  final OtpPurpose  purpose;
  final String?     name; // Required for registration purpose

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.purpose,
    this.name,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen>
    with WidgetsBindingObserver {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();
  String _otp      = '';
  bool   _isVerifying = false;
  String _errorMsg    = '';

  static const _cooldownSeconds = 60;
  int    _cooldown    = 0;
  bool   _isResending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_onOtpChanged);
    _startCooldown();
    // Delay focus request slightly so the keyboard reliably shows on first load
    // and after returning from another app (addPostFrameCallback alone can race
    // Android's window-focus restoration and silently fail).
    Future.delayed(const Duration(milliseconds: 300), _requestFocus);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Wait for Android's window-focus restoration before requesting focus.
      Future.delayed(const Duration(milliseconds: 400), _requestFocus);
    }
  }

  void _requestFocus() {
    if (!mounted || _otp.length >= 6 || _isVerifying) return;
    _focusNode.requestFocus();
    // requestFocus() updates Flutter's focus tree but doesn't always tell the
    // Android OS to show the keyboard (the two are decoupled on Android).
    // TextInput.show directly instructs the input method to become visible.
    Future.microtask(
      () => SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
    );
  }

  void _onOtpChanged() {
    final raw     = _ctrl.text.replaceAll(RegExp(r'\D'), '');
    final clamped = raw.length > 6 ? raw.substring(0, 6) : raw;
    if (_ctrl.text != clamped) {
      _ctrl.value = _ctrl.value.copyWith(
        text:      clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
        composing: TextRange.empty,
      );
    }
    // Only clear the error when the user actively types a new digit.
    // When _ctrl.clear() is called programmatically (after a failed verify),
    // clamped will be empty — we must NOT clear _errorMsg or the error
    // disappears instantly before the user can read it.
    setState(() {
      _otp = clamped;
      if (clamped.isNotEmpty) _errorMsg = '';
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

    final OtpResult result;
    switch (widget.purpose) {
      case OtpPurpose.registration:
        result = await OtpService.instance.requestRegistrationOtp(widget.email);
      case OtpPurpose.emailVerification:
        result = await OtpService.instance.requestEmailVerificationOtp();
      case OtpPurpose.passwordReset:
        result = await OtpService.instance.requestPasswordResetOtp(widget.email);
    }

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

    switch (widget.purpose) {
      case OtpPurpose.registration:
        await _verifyRegistrationOtp();
      case OtpPurpose.emailVerification:
        await _verifyEmailOtp();
      case OtpPurpose.passwordReset:
        await _verifyResetOtp();
    }
  }

  Future<void> _verifyRegistrationOtp() async {
    final result = await OtpService.instance.verifyRegistrationOtp(widget.email, _otp);
    if (!mounted) return;

    if (result.success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PasswordSetupScreen(
            name:  widget.name ?? '',
            email: widget.email,
          ),
        ),
      );
    } else {
      setState(() {
        _isVerifying = false;
        _errorMsg    = result.error ?? 'Verification failed.';
        _ctrl.clear();
      });
      Future.delayed(const Duration(milliseconds: 200), _requestFocus);
    }
  }

  Future<void> _verifyEmailOtp() async {
    final result = await OtpService.instance.verifyEmailOtp(_otp);
    if (!mounted) return;

    if (result.success) {
      await context.read<AuthProvider>().checkEmailVerification();
      // AuthWrapper rebuilds and routes to MainNavigation automatically.
    } else {
      setState(() {
        _isVerifying = false;
        _errorMsg    = result.error ?? 'Verification failed.';
        _ctrl.clear();
      });
      Future.delayed(const Duration(milliseconds: 200), _requestFocus);
    }
  }

  Future<void> _verifyResetOtp() async {
    // OTP validated together with the new password in ResetPasswordScreen
    // to avoid a double round-trip.
    if (!mounted) return;
    setState(() => _isVerifying = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(email: widget.email, otp: _otp),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isReset  = widget.purpose == OtpPurpose.passwordReset;
    final title    = isReset ? 'Enter Reset Code' : 'Verify Your Email';
    final subtitle = isReset
        ? 'We\'ve sent a 6-digit reset code to'
        : 'We\'ve sent a 6-digit verification code to';
    final icon     = isReset
        ? Icons.lock_reset_rounded
        : Icons.mark_email_unread_rounded;
    final btnLabel = switch (widget.purpose) {
      OtpPurpose.registration      => 'Confirm Email',
      OtpPurpose.emailVerification => 'Verify Email',
      OtpPurpose.passwordReset     => 'Continue',
    };

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

              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: AppConstants.primaryColor),
              ),
              const SizedBox(height: 28),

              Text(title, style: AppConstants.headingStyle, textAlign: TextAlign.center),
              const SizedBox(height: 12),

              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], height: 1.5)),
              const SizedBox(height: 4),
              Text(widget.email,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 36),

              // ── OTP boxes ────────────────────────────────────────────────
              Stack(
                alignment: Alignment.center,
                children: [
                  // Hidden input — must have non-trivial size so Android's
                  // InputMethodManager considers the view eligible for the keyboard.
                  Positioned(
                    left: -9999,
                    child: SizedBox(
                      width: 1,
                      height: 48,
                      child: TextField(
                        controller:      _ctrl,
                        focusNode:       _focusNode,
                        keyboardType:    TextInputType.number,
                        maxLength:       6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _requestFocus,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, _buildBox),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _errorMsg.isNotEmpty
                    ? Container(
                        key: const ValueKey('err'),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppConstants.errorColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppConstants.errorColor, size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(_errorMsg,
                                  style: const TextStyle(
                                      color: AppConstants.errorColor, fontSize: 13)),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(key: ValueKey('no-err'), height: 0),
              ),

              const SizedBox(height: 32),

              if (_isVerifying)
                Column(
                  children: [
                    const CircularProgressIndicator(color: AppConstants.primaryColor),
                    const SizedBox(height: 12),
                    Text('Verifying…', style: TextStyle(color: Colors.grey[500])),
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
                    child: Text(btnLabel,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Didn't get a code? ",
                      style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  _cooldown > 0
                      ? Text('Resend in ${_cooldown}s',
                          style: TextStyle(color: Colors.grey[400], fontSize: 14))
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

  Widget _buildBox(int i) {
    final filled    = i < _otp.length;
    final isCursor  = i == _otp.length && _focusNode.hasFocus;
    final hasError  = _errorMsg.isNotEmpty;
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
        color: filled ? AppConstants.primaryColor.withValues(alpha: 0.06) : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isCursor ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: filled
          ? Text(_otp[i],
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: hasError ? AppConstants.errorColor : Colors.black87,
              ))
          : isCursor
              ? Container(width: 2, height: 24, color: AppConstants.primaryColor)
              : null,
    );
  }
}

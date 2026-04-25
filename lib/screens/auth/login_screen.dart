import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/secure_storage_manager.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_button.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey           = GlobalKey<FormState>();
  final _emailController   = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _prefillEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _prefillEmail() async {
    final last = await SecureStorageManager.instance.getLastEmail();
    if (last != null && mounted) {
      setState(() => _emailController.text = last);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    context.read<AuthProvider>().clearError();
    if (!_formKey.currentState!.validate()) return;

    await context.read<AuthProvider>().signIn(
          email:    _emailController.text,
          password: _passwordController.text,
        );
    // AuthWrapper handles navigation on success.
  }

  void _navigateToForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          prefillEmail: _emailController.text.trim().isNotEmpty
              ? _emailController.text.trim()
              : null,
        ),
      ),
    );
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.largePadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),

                Icon(
                  Icons.receipt_long_rounded,
                  size: 80,
                  color: AppConstants.primaryColor,
                ),
                const SizedBox(height: 24),

                Text(
                  AppConstants.appName,
                  style: AppConstants.headingStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                Text(
                  'Split bills, not friendships',
                  style: AppConstants.subheadingStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Email field
                CustomTextField(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'Enter your email',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
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
                const SizedBox(height: 16),

                // Password field
                CustomTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Enter your password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return AppConstants.passwordRequired;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),

                // Forgot password link — opens dedicated screen
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _navigateToForgotPassword,
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(color: AppConstants.primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Error banner
                Consumer<AuthProvider>(
                  builder: (_, auth, _) {
                    if (auth.errorMessage == null) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.all(AppConstants.defaultPadding),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppConstants.errorColor.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(
                          color:
                              AppConstants.errorColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppConstants.errorColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: const TextStyle(
                                  color: AppConstants.errorColor),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Sign-in button
                Consumer<AuthProvider>(
                  builder: (_, auth, _) => CustomButton(
                    text: 'Sign In',
                    onPressed: _handleLogin,
                    isLoading: auth.isLoading,
                    icon: Icons.login,
                  ),
                ),

                const SizedBox(height: 24),

                // Register link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Colors.black54),
                    ),
                    GestureDetector(
                      onTap: _navigateToRegister,
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: AppConstants.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/password_strength.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_button.dart';

// ── Password strength bar (3-segment indicator) ────────────────────────────

class _StrengthBar extends StatelessWidget {
  final PasswordStrength strength;
  const _StrengthBar({required this.strength});

  @override
  Widget build(BuildContext context) {
    if (strength == PasswordStrength.empty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: List.generate(3, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i < strength.filledSegments
                      ? strength.color
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          'Password strength: ${strength.label}',
          style: TextStyle(color: strength.color, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey                 = GlobalKey<FormState>();
  final _nameController          = TextEditingController();
  final _emailController         = TextEditingController();
  final _passwordController      = TextEditingController();
  final _confirmController       = TextEditingController();

  bool             _obscurePassword = true;
  bool             _obscureConfirm  = true;
  PasswordStrength _strength        = PasswordStrength.empty;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      setState(() => _strength = measurePasswordStrength(_passwordController.text));
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    context.read<AuthProvider>().clearError();
    if (!_formKey.currentState!.validate()) return;

    final success = await context.read<AuthProvider>().register(
          name:     _nameController.text,
          email:    _emailController.text,
          password: _passwordController.text,
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Please verify your email.'),
          backgroundColor: AppConstants.successColor,
        ),
      );
      // AuthWrapper will route to EmailVerificationScreen automatically.
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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

                Text(
                  'Create Account',
                  style: AppConstants.headingStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Join SmartSplit and start splitting bills easily',
                  style: AppConstants.subheadingStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Full name
                CustomTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Enter your full name',
                  prefixIcon: Icons.person_outline,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return AppConstants.nameRequired;
                    }
                    if (v.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
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

                // Password
                CustomTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Create a strong password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
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
                    if (v.length < 8) return 'Password must be at least 8 characters';
                    return null;
                  },
                ),

                // Strength meter
                _StrengthBar(strength: _strength),
                const SizedBox(height: 16),

                // Confirm password
                CustomTextField(
                  controller: _confirmController,
                  label: 'Confirm Password',
                  hint: 'Confirm your password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleRegister(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (v != _passwordController.text) {
                      return AppConstants.passwordsDoNotMatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Password requirements hint
                Container(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius:
                        BorderRadius.circular(AppConstants.borderRadius),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: Colors.blue, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Strong password tips',
                            style: TextStyle(
                                color: Colors.blue[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...const [
                        '• At least 8 characters',
                        '• Uppercase and lowercase letters',
                        '• At least one number',
                        '• A special character (!@#\$ etc.)',
                      ].map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(t,
                              style: TextStyle(
                                  color: Colors.blue[700], fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Error banner
                Consumer<AuthProvider>(
                  builder: (_, auth, _) {
                    if (auth.errorMessage == null) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding:
                          const EdgeInsets.all(AppConstants.defaultPadding),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color:
                            AppConstants.errorColor.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(
                          color: AppConstants.errorColor.withValues(alpha: 0.3),
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

                Consumer<AuthProvider>(
                  builder: (_, auth, _) => CustomButton(
                    text: 'Create Account',
                    onPressed: _handleRegister,
                    isLoading: auth.isLoading,
                    icon: Icons.person_add,
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Colors.black54),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Sign In',
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

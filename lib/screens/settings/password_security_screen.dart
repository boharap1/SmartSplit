import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';

class PasswordSecurityScreen extends StatefulWidget {
  const PasswordSecurityScreen({super.key});

  @override
  State<PasswordSecurityScreen> createState() =>
      _PasswordSecurityScreenState();
}

class _PasswordSecurityScreenState extends State<PasswordSecurityScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _currentCtrl  = TextEditingController();
  final _newCtrl      = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _showCurrent   = false;
  bool _showNew       = false;
  bool _showConfirm   = false;
  bool _isSaving      = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Password strength ──────────────────────────────────────────────────────

  int _strength(String p) {
    int score = 0;
    if (p.length >= 8)                      score++;
    if (RegExp(r'[A-Z]').hasMatch(p))       score++;
    if (RegExp(r'[a-z]').hasMatch(p))       score++;
    if (RegExp(r'[0-9]').hasMatch(p))       score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score;
  }

  Color _strengthColor(int s) {
    if (s <= 1) return AppConstants.errorColor;
    if (s <= 3) return const Color(0xFFFFB300);
    return AppConstants.successColor;
  }

  String _strengthLabel(int s) {
    if (s <= 1) return 'Weak';
    if (s <= 3) return 'Fair';
    return 'Strong';
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    final success = await context.read<AuthProvider>().changePassword(
          currentPassword: _currentCtrl.text,
          newPassword:     _newCtrl.text,
        );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password changed successfully!'),
          backgroundColor: AppConstants.successColor,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<AuthProvider>().errorMessage ??
                  'Failed to change password.'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final newVal  = _newCtrl.text;
    final s       = _strength(newVal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Password & Security'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.largePadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCard([
                _field(
                  controller:  _currentCtrl,
                  label:       'Current Password',
                  icon:        Icons.lock_outline_rounded,
                  obscure:     !_showCurrent,
                  showToggle:  _showCurrent,
                  onToggle:    () => setState(() => _showCurrent = !_showCurrent),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter your current password' : null,
                ),
              ]),

              const SizedBox(height: 16),
              _sectionLabel('New Password'),
              _sectionCard([
                _field(
                  controller:  _newCtrl,
                  label:       'New Password',
                  icon:        Icons.lock_reset_rounded,
                  obscure:     !_showNew,
                  showToggle:  _showNew,
                  onToggle:    () => setState(() => _showNew = !_showNew),
                  onChanged:   (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a new password';
                    if (v.length < 6) return 'Password must be at least 6 characters';
                    if (v == _currentCtrl.text) return 'New password must differ from current';
                    return null;
                  },
                ),
                if (newVal.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: s / 5,
                                  minHeight: 4,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation(
                                      _strengthColor(s)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _strengthLabel(s),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _strengthColor(s),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _strengthHints(newVal),
                      ],
                    ),
                  ),
                ],
                _field(
                  controller:  _confirmCtrl,
                  label:       'Confirm New Password',
                  icon:        Icons.check_circle_outline_rounded,
                  obscure:     !_showConfirm,
                  showToggle:  _showConfirm,
                  onToggle:    () => setState(() => _showConfirm = !_showConfirm),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please confirm your password';
                    if (v != _newCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ]),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.borderRadius),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Change Password',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 24),
              _securityTips(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────────────────────

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey[500],
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _sectionCard(List<Widget> children) => Container(
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
        child: Column(children: children),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscure,
    required bool showToggle,
    required VoidCallback onToggle,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextFormField(
        controller:  controller,
        obscureText: obscure,
        onChanged:   onChanged,
        validator:   validator,
        enabled:     !_isSaving,
        decoration: InputDecoration(
          labelText:  label,
          prefixIcon: Icon(icon, color: AppConstants.primaryColor, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              showToggle ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.grey[400],
              size: 20,
            ),
            onPressed: onToggle,
          ),
          filled:         true,
          fillColor:      Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            borderSide: const BorderSide(
                color: AppConstants.primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            borderSide:
                const BorderSide(color: AppConstants.errorColor),
          ),
        ),
      ),
    );
  }

  Widget _strengthHints(String p) {
    final checks = [
      ('8+ characters',         p.length >= 8),
      ('Uppercase letter',      RegExp(r'[A-Z]').hasMatch(p)),
      ('Lowercase letter',      RegExp(r'[a-z]').hasMatch(p)),
      ('Number',                RegExp(r'[0-9]').hasMatch(p)),
      ('Special character',     RegExp(r'[^A-Za-z0-9]').hasMatch(p)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: checks.map((c) {
        final (label, met) = c;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              met ? Icons.check_rounded : Icons.circle_outlined,
              size: 11,
              color: met ? AppConstants.successColor : Colors.grey[400],
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: met ? AppConstants.successColor : Colors.grey[400],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _securityTips() => Container(
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
            Text('Security Tips',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            _tip(Icons.lock_outline_rounded,
                'Use a unique password not used on other sites.'),
            const SizedBox(height: 8),
            _tip(Icons.update_rounded,
                'Change your password regularly.'),
            const SizedBox(height: 8),
            _tip(Icons.phonelink_lock_outlined,
                'Never share your password with anyone.'),
          ],
        ),
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

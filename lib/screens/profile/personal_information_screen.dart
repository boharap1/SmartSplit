import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import 'verify_account_screen.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState
    extends State<PersonalInformationScreen> {
  bool _isSaving = false;

  // ── Field editors ─────────────────────────────────────────────────────────

  Future<void> _editPhone() async {
    final user       = context.read<AuthProvider>().user;
    final controller = TextEditingController(text: user?.phoneNumber ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Phone Number'),
        content: TextFormField(
          controller:   controller,
          autofocus:    true,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\+\-\(\)\s]')),
          ],
          decoration: InputDecoration(
            hintText:   '+44 7xxx xxxxxx',
            prefixIcon: const Icon(Icons.phone_outlined,
                color: AppConstants.primaryColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:     const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final digits =
                  controller.text.replaceAll(RegExp(r'\D'), '');
              if (controller.text.isNotEmpty &&
                  (digits.length < 7 || digits.length > 15)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Enter a valid phone number')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (confirmed != true || !mounted) return;

    await _saveField(phoneNumber: controller.text.trim());
  }

  Future<void> _editDob() async {
    final user    = context.read<AuthProvider>().user;
    DateTime init = DateTime(1990);
    if (user?.dob?.isNotEmpty == true) {
      try {
        init = DateTime.parse(user!.dob!);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context:      context,
      initialDate:  init,
      firstDate:    DateTime(1900),
      lastDate:     DateTime.now().subtract(const Duration(days: 365 * 13)),
      helpText:     'Select Date of Birth',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppConstants.primaryColor,
          ),
        ),
        child: child!,
      ),
    );

    if (picked == null || !mounted) return;
    await _saveField(dob: DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _editGender() async {
    const options = [
      'Male',
      'Female',
      'Non-binary',
      'Prefer not to say',
    ];
    final current = context.read<AuthProvider>().user?.gender;

    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape:   const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  'Select Gender',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              const Divider(height: 1),
              ...options.map((opt) => ListTile(
                    title: Text(opt),
                    trailing: current == opt
                        ? const Icon(Icons.check_rounded,
                            color: AppConstants.primaryColor)
                        : null,
                    onTap: () => Navigator.pop(ctx, opt),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (chosen == null || !mounted) return;
    await _saveField(gender: chosen);
  }

  Future<void> _saveField({
    String? phoneNumber,
    String? dob,
    String? gender,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final success = await context.read<AuthProvider>().updateProfile(
          phoneNumber: phoneNumber,
          dob:         dob,
          gender:      gender,
        );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<AuthProvider>().errorMessage ??
                  'Failed to update.'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user       = context.watch<AuthProvider>().user;
    final isVerified = context.watch<AuthProvider>().isEmailVerified;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Information'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isSaving
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppConstants.primaryColor),
            )
          : ListView(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              children: [
                // ── Account info ─────────────────────────────────────
                _sectionLabel('Account'),
                _card([
                  _row(
                    icon:      Icons.email_outlined,
                    iconColor: AppConstants.primaryColor,
                    label:     'Email',
                    value:     user?.email ?? '—',
                    trailing:  const Icon(Icons.lock_outline_rounded,
                        size: 16, color: Colors.grey),
                  ),
                  _divider(),
                  _row(
                    icon:      Icons.phone_outlined,
                    iconColor: const Color(0xFF26A69A),
                    label:     'Phone',
                    value:     _orNotSet(user?.phoneNumber),
                    onEdit:    _editPhone,
                  ),
                  _divider(),
                  _row(
                    icon:      Icons.cake_outlined,
                    iconColor: const Color(0xFFFF7043),
                    label:     'Date of Birth',
                    value:     _formatDob(user?.dob),
                    onEdit:    _editDob,
                  ),
                  _divider(),
                  _row(
                    icon:      Icons.wc_outlined,
                    iconColor: const Color(0xFF5C6BC0),
                    label:     'Gender',
                    value:     _orNotSet(user?.gender),
                    onEdit:    _editGender,
                  ),
                ]),

                const SizedBox(height: 20),

                // ── Account status ────────────────────────────────────
                _sectionLabel('Account Status'),
                _card([
                  _row(
                    icon:      Icons.calendar_today_outlined,
                    iconColor: const Color(0xFF78909C),
                    label:     'Member Since',
                    value:     user != null
                        ? DateFormat('d MMMM yyyy').format(user.createdAt)
                        : '—',
                  ),
                  _divider(),
                  // Verification status row — tappable if not verified
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: isVerified
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const VerifyAccountScreen(),
                              ),
                            ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          _iconBox(
                            Icons.verified_user_outlined,
                            isVerified
                                ? AppConstants.successColor
                                : const Color(0xFFFFB300),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Verification Status',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: (isVerified
                                                ? AppConstants.successColor
                                                : const Color(0xFFFFB300))
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isVerified
                                                ? Icons.check_circle_outline
                                                : Icons.warning_amber_rounded,
                                            size: 13,
                                            color: isVerified
                                                ? AppConstants.successColor
                                                : const Color(0xFFFFB300),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isVerified
                                                ? 'Verified'
                                                : 'Not Verified',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isVerified
                                                  ? AppConstants.successColor
                                                  : const Color(0xFFFFB300),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!isVerified)
                            Text(
                              'Verify →',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppConstants.primaryColor,
                                  fontWeight: FontWeight.w500),
                            ),
                        ],
                      ),
                    ),
                  ),
                ]),

                const SizedBox(height: 24),
              ],
            ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize:      11,
            fontWeight:    FontWeight.w700,
            color:         Colors.grey[500],
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        margin:     const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(children: children),
      );

  Widget _row({
    required IconData icon,
    required Color    iconColor,
    required String   label,
    required String   value,
    Widget?           trailing,
    VoidCallback?     onEdit,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          _iconBox(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          ?trailing,
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color:        AppConstants.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit_outlined,
                    size: 16, color: AppConstants.primaryColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) => Container(
        padding:    const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: color),
      );

  Widget _divider() => Padding(
        padding:
            const EdgeInsets.only(left: 58, right: 0),
        child: Divider(height: 1, color: Colors.grey[100]),
      );

  String _orNotSet(String? v) =>
      (v != null && v.isNotEmpty) ? v : 'Not set';

  String _formatDob(String? dob) {
    if (dob == null || dob.isEmpty) return 'Not set';
    try {
      return DateFormat('d MMMM yyyy').format(DateTime.parse(dob));
    } catch (_) {
      return dob;
    }
  }
}

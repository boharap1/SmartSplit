import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<SettingsProvider>().language;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Language'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              itemCount: SettingsProvider.languages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final lang = SettingsProvider.languages[i];
                final isSelected = lang['name'] == current;
                return _LanguageTile(
                  name:       lang['name']!,
                  native:     lang['native']!,
                  isSelected: isSelected,
                  onTap: () => _select(ctx, lang['name']!),
                );
              },
            ),
          ),
          _comingSoonNote(),
        ],
      ),
    );
  }

  Future<void> _select(BuildContext context, String name) async {
    await context.read<SettingsProvider>().setLanguage(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Language set to $name'),
        backgroundColor: AppConstants.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _infoCard() => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppConstants.primaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppConstants.primaryColor, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Full in-app translation is coming in a future update. '
                'Your preference is saved and will apply once available.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      );

  Widget _comingSoonNote() => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'More languages coming soon.',
          style: TextStyle(fontSize: 12, color: Colors.grey[400]),
          textAlign: TextAlign.center,
        ),
      );
}

class _LanguageTile extends StatelessWidget {
  final String name;
  final String native;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.name,
    required this.native,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: isSelected
            ? AppConstants.primaryColor.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? AppConstants.primaryColor.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      native,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppConstants.primaryColor
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppConstants.primaryColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants.dart';

class CurrencyScreen extends StatelessWidget {
  const CurrencyScreen({super.key});

  static const _currencies = [
    {'code': 'GBP', 'flag': '🇬🇧'},
    {'code': 'USD', 'flag': '🇺🇸'},
    {'code': 'EUR', 'flag': '🇪🇺'},
    {'code': 'NPR', 'flag': '🇳🇵'},
    {'code': 'INR', 'flag': '🇮🇳'},
    {'code': 'AUD', 'flag': '🇦🇺'},
    {'code': 'CAD', 'flag': '🇨🇦'},
    {'code': 'JPY', 'flag': '🇯🇵'},
    {'code': 'SGD', 'flag': '🇸🇬'},
    {'code': 'AED', 'flag': '🇦🇪'},
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final current  = settings.currency;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Currency'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(settings),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              itemCount: _currencies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final c          = _currencies[i];
                final code       = c['code']!;
                final isSelected = code == current;
                return _CurrencyTile(
                  code:       code,
                  name:       SettingsProvider.currencyNames[code] ?? code,
                  symbol:     settings.currencySymbol,
                  flag:       c['flag']!,
                  isSelected: isSelected,
                  onTap: () => _select(ctx, code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(SettingsProvider settings) => Container(
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
                'Changing currency updates all amount displays across the app. '
                'Current: ${settings.currencySymbol} ${settings.currency}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      );

  Future<void> _select(BuildContext context, String code) async {
    await context.read<SettingsProvider>().setCurrency(code);
    if (!context.mounted) return;
    final sym = context.read<SettingsProvider>().currencySymbol;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Currency set to $code ($sym)'),
        backgroundColor: AppConstants.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  final String code;
  final String name;
  final String symbol;
  final String flag;
  final bool isSelected;
  final VoidCallback onTap;

  const _CurrencyTile({
    required this.code,
    required this.name,
    required this.symbol,
    required this.flag,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? AppConstants.primaryColor
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$code · $symbol',
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

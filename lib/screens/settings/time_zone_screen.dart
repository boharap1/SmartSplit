import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants.dart';

class TimeZoneScreen extends StatefulWidget {
  const TimeZoneScreen({super.key});

  @override
  State<TimeZoneScreen> createState() => _TimeZoneScreenState();
}

class _TimeZoneScreenState extends State<TimeZoneScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filtered {
    if (_query.isEmpty) return SettingsProvider.timeZones;
    final q = _query.toLowerCase();
    return SettingsProvider.timeZones
        .where((tz) =>
            tz['label']!.toLowerCase().contains(q) ||
            tz['id']!.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _select(String id, String label) async {
    await context.read<SettingsProvider>().setTimeZone(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Time zone set to $label'),
        backgroundColor: AppConstants.successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = context.watch<SettingsProvider>().timeZone;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Zone'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          _searchBar(),
          Expanded(
            child: filtered.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final tz = filtered[i];
                      final isSelected = tz['id'] == current;
                      return _TimeZoneTile(
                        id:         tz['id']!,
                        label:      tz['label']!,
                        isSelected: isSelected,
                        onTap: () => _select(tz['id']!, tz['label']!),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search time zones…',
            prefixIcon: const Icon(Icons.search_rounded,
                color: AppConstants.primaryColor),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No time zones found',
                style: TextStyle(color: Colors.grey[400])),
          ],
        ),
      );
}

class _TimeZoneTile extends StatelessWidget {
  final String id;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimeZoneTile({
    required this.id,
    required this.label,
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
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: (isSelected
                          ? AppConstants.primaryColor
                          : Colors.grey[400]!)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: isSelected ? AppConstants.primaryColor : Colors.grey[500],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                    color:
                        isSelected ? AppConstants.primaryColor : Colors.black87,
                  ),
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

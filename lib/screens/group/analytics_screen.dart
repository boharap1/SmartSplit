import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/group_model.dart';
import '../../models/analytics_model.dart';
import '../../services/analytics_service.dart';
import '../../utils/constants.dart';

enum TimePeriod { last7Days, lastMonth, annual, custom }

class AnalyticsScreen extends StatefulWidget {
  final GroupModel group;

  const AnalyticsScreen({super.key, required this.group});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final AnalyticsService _analyticsService = AnalyticsService();
  GroupAnalytics? _fullAnalytics;
  GroupAnalytics? _filteredAnalytics;
  bool _isLoading = true;
  int _touchedIndex = -1;

  TimePeriod _selectedPeriod = TimePeriod.lastMonth;
  DateTime? _selectedMonth;
  List<DateTime> _availableMonths = [];

  final List<Color> _categoryColors = [
    const Color(0xFF009688),
    const Color(0xFF4CAF50),
    const Color(0xFF2196F3),
    const Color(0xFFFF9800),
    const Color(0xFFE91E63),
    const Color(0xFF9C27B0),
    const Color(0xFF795548),
    const Color(0xFF607D8B),
    const Color(0xFFFF5722),
    const Color(0xFF3F51B5),
  ];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    final analytics = await _analyticsService.getGroupAnalytics(
      widget.group.groupId,
      widget.group.members,
    );

    // Extract available months from expenses
    final Set<DateTime> monthsSet = {};
    for (final expense in analytics.rawExpenses) {
      monthsSet.add(DateTime(expense.date.year, expense.date.month));
    }
    final months = monthsSet.toList()..sort((a, b) => a.compareTo(b));

    setState(() {
      _fullAnalytics = analytics;
      _availableMonths = months;
      if (_selectedMonth == null && months.isNotEmpty) {
        _selectedMonth = months.last;
      }
      _isLoading = false;
    });

    // Apply initial filter
    _applyFilter();
  }

  void _applyFilter() {
    if (_fullAnalytics == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime startDate;
    DateTime endDate;

    switch (_selectedPeriod) {
      case TimePeriod.last7Days:
        startDate = today.subtract(const Duration(days: 6));
        endDate = today.add(const Duration(days: 1));
        break;
      case TimePeriod.lastMonth:
        startDate = today.subtract(const Duration(days: 30));
        endDate = today.add(const Duration(days: 1));
        break;
      case TimePeriod.annual:
        startDate = DateTime(now.year, 1, 1);
        endDate = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
      case TimePeriod.custom:
        if (_selectedMonth == null) {
          setState(() => _filteredAnalytics = _fullAnalytics);
          return;
        }
        startDate = DateTime(_selectedMonth!.year, _selectedMonth!.month, 1);
        endDate = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 0, 23, 59, 59);
        break;
    }

    final filtered = _analyticsService.filterAnalyticsByDate(
      _fullAnalytics!,
      startDate,
      endDate,
    );

    setState(() => _filteredAnalytics = filtered);
  }

  GroupAnalytics get _currentAnalytics => _filteredAnalytics ?? _fullAnalytics!;

  String get _periodLabel {
    switch (_selectedPeriod) {
      case TimePeriod.last7Days:
        return 'Last 7 Days';
      case TimePeriod.lastMonth:
        return 'Last 30 Days';
      case TimePeriod.annual:
        return 'Year ${DateTime.now().year}';
      case TimePeriod.custom:
        if (_selectedMonth != null) {
          return _formatMonth(_selectedMonth!);
        }
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: AppConstants.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppConstants.primaryColor),
            )
          : _fullAnalytics == null || _fullAnalytics!.rawExpenses.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadAnalytics,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTimePeriodSelector(),
                        Padding(
                          padding: const EdgeInsets.all(AppConstants.defaultPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSummaryCards(),
                              const SizedBox(height: 24),
                              _buildCategoryChart(),
                              const SizedBox(height: 24),
                              _buildMonthlyChart(),
                              const SizedBox(height: 24),
                              _buildTopSpenders(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildTimePeriodSelector() {
    return Container(
      color: AppConstants.primaryColor,
      child: Column(
        children: [
          // Period toggle buttons
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildPeriodButton('7 Days', TimePeriod.last7Days),
                _buildPeriodButton('30 Days', TimePeriod.lastMonth),
                _buildPeriodButton('Annual', TimePeriod.annual),
                _buildPeriodButton('Custom', TimePeriod.custom),
              ],
            ),
          ),

          // Month selector (only visible when Custom is selected)
          if (_selectedPeriod == TimePeriod.custom && _availableMonths.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<DateTime>(
                  value: _selectedMonth,
                  isExpanded: true,
                  icon: const Icon(Icons.calendar_month, color: AppConstants.primaryColor),
                  items: _availableMonths.map((month) {
                    return DropdownMenuItem(
                      value: month,
                      child: Text(
                        _formatMonth(month),
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedMonth = value);
                    _applyFilter();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String label, TimePeriod period) {
    final isSelected = _selectedPeriod == period;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedPeriod = period);
          _applyFilter();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppConstants.primaryColor : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  String _formatMonth(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No Data Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Add some expenses to see analytics',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final analytics = _currentAnalytics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _periodLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppConstants.primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Total Spent',
                '£${analytics.totalExpenses.toStringAsFixed(2)}',
                Icons.account_balance_wallet,
                AppConstants.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Expenses',
                '${analytics.expenseCount}',
                Icons.receipt_long,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Average',
                analytics.expenseCount > 0
                    ? '£${analytics.averageExpense.toStringAsFixed(2)}'
                    : '£0.00',
                Icons.trending_up,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Top Category',
                analytics.topCategory ?? 'N/A',
                Icons.category,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart() {
    final analytics = _currentAnalytics;

    if (analytics.categoryBreakdown.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No expenses in this period',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart, color: AppConstants.primaryColor, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Spending by Category',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${analytics.categoryBreakdown.length} categories',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sections: _buildPieSections(analytics),
                sectionsSpace: 3,
                centerSpaceRadius: 50,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          // Full legend with accurate percentages
          ...analytics.categoryBreakdown.asMap().entries.map((entry) {
            final index = entry.key;
            final category = entry.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _categoryColors[index % _categoryColors.length],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      category.category,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(
                    '${category.count} expense${category.count != 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '£${category.amount.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _categoryColors[index % _categoryColors.length].withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${category.percentage.toStringAsFixed(1)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _categoryColors[index % _categoryColors.length],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(GroupAnalytics analytics) {
    return List.generate(analytics.categoryBreakdown.length, (index) {
      final category = analytics.categoryBreakdown[index];
      final isTouched = index == _touchedIndex;
      final radius = isTouched ? 65.0 : 55.0;
      final fontSize = isTouched ? 14.0 : 11.0;

      return PieChartSectionData(
        color: _categoryColors[index % _categoryColors.length],
        value: category.amount,
        title: isTouched
            ? '${category.percentage.toStringAsFixed(1)}%'
            : category.percentage >= 8
                ? '${category.percentage.toStringAsFixed(0)}%'
                : '',
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    });
  }

  Widget _buildMonthlyChart() {
    // Always show full data for monthly chart
    final analytics = _fullAnalytics!;

    if (analytics.monthlySpending.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxAmount = analytics.monthlySpending
        .map((e) => e.amount)
        .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            AppConstants.primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.bar_chart, color: AppConstants.primaryColor, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Monthly Trend',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${analytics.monthlySpending.length} months',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppConstants.primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'All time data',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 240,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxAmount * 1.25,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipMargin: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final monthly = analytics.monthlySpending[group.x.toInt()];
                      return BarTooltipItem(
                        '${monthly.monthName} ${monthly.year}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '£${monthly.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: '\n${monthly.expenseCount} expense${monthly.expenseCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= analytics.monthlySpending.length) {
                          return const SizedBox.shrink();
                        }
                        final monthly = analytics.monthlySpending[value.toInt()];
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            children: [
                              Text(
                                monthly.monthName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${monthly.year}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      reservedSize: 40,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: maxAmount / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '£${value.toInt()}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxAmount / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withOpacity(0.15),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                barGroups: analytics.monthlySpending.asMap().entries.map((entry) {
                  final index = entry.key;
                  final isLast = index == analytics.monthlySpending.length - 1;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.amount,
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: isLast
                              ? [
                                  AppConstants.primaryColor,
                                  AppConstants.secondaryColor,
                                ]
                              : [
                                  AppConstants.primaryColor.withOpacity(0.7),
                                  AppConstants.primaryColor.withOpacity(0.9),
                                ],
                        ),
                        width: 24,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          topRight: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSpenders() {
    final analytics = _currentAnalytics;

    if (analytics.userSpending.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'No contributions in this period',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // Calculate total for accurate contribution percentage
    final totalPaid = analytics.userSpending.fold(0.0, (sum, u) => sum + u.totalPaid);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people, color: AppConstants.primaryColor, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Member Contributions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _periodLabel,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Total: £${totalPaid.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ...analytics.userSpending.asMap().entries.map((entry) {
            final index = entry.key;
            final user = entry.value;
            final contributionPercent = totalPaid > 0 ? (user.totalPaid / totalPaid) * 100 : 0.0;
            final progress = totalPaid > 0 ? user.totalPaid / totalPaid : 0.0;

            // Medal colors for top 3
            Color? medalColor;
            IconData? medalIcon;
            if (index == 0 && user.totalPaid > 0) {
              medalColor = const Color(0xFFFFD700);
              medalIcon = Icons.emoji_events;
            } else if (index == 1 && user.totalPaid > 0) {
              medalColor = const Color(0xFFC0C0C0);
              medalIcon = Icons.emoji_events;
            } else if (index == 2 && user.totalPaid > 0) {
              medalColor = const Color(0xFFCD7F32);
              medalIcon = Icons.emoji_events;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: index == 0
                    ? AppConstants.primaryColor.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: index == 0
                    ? Border.all(color: AppConstants.primaryColor.withOpacity(0.2))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Position or medal
                      if (medalIcon != null)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: medalColor!.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(medalIcon, color: medalColor, size: 18),
                        )
                      else
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              '${user.expenseCount} expense${user.expenseCount != 1 ? 's' : ''} paid',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '£${user.totalPaid.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppConstants.primaryColor,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${contributionPercent.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        index == 0
                            ? AppConstants.primaryColor
                            : AppConstants.primaryColor.withOpacity(0.6),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
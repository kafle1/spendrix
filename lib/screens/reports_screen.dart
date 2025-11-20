import 'package:flutter/material.dart' hide TextStyle, Colors, BorderRadius;
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/data_provider.dart';
import '../models/category.dart' as app_models;
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';
import 'package:flutter/painting.dart' show TextStyle, BorderRadius;
import 'package:flutter/material.dart' show Colors;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedPeriod = 'This Month';

  @override
  void initState() {
    super.initState();
    _setThisMonth();
  }

  void _setThisMonth() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  }

  void _setLastMonth() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month - 1, 1);
    _endDate = DateTime(now.year, now.month, 0, 23, 59, 59);
  }

  void _setThisYear() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, 1, 1);
    _endDate = DateTime(now.year, 12, 31, 23, 59, 59);
  }

  Future<void> _setCustomPeriod() async {
    final dateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark
                ? ColorScheme.dark(
                    primary: AppColors.primary,
                    onPrimary: Colors.white,
                    surface: AppColors.darkSurface,
                    onSurface: AppColors.darkTextPrimary,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primary,
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: AppColors.textPrimary,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (dateRange != null) {
      setState(() {
        _startDate = DateTime(
          dateRange.start.year,
          dateRange.start.month,
          dateRange.start.day,
          0,
          0,
          0,
        );
        _endDate = DateTime(
          dateRange.end.year,
          dateRange.end.month,
          dateRange.end.day,
          23,
          59,
          59,
        );
        _selectedPeriod = 'Custom';
      });
      
      if (mounted) {
        final dataProvider = Provider.of<DataProvider>(context, listen: false);
        await dataProvider.loadTransactions(
          startDate: _startDate,
          endDate: _endDate,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Reports & Analytics',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: PopupMenuButton<String>(
              onSelected: (value) async {
                setState(() {
                  _selectedPeriod = value;
                });
                
                switch (value) {
                  case 'This Month':
                    _setThisMonth();
                    break;
                  case 'Last Month':
                    _setLastMonth();
                    break;
                  case 'This Year':
                    _setThisYear();
                    break;
                  case 'Custom':
                    await _setCustomPeriod();
                    return;
                }
                
                if (mounted) {
                  final dataProvider = Provider.of<DataProvider>(context, listen: false);
                  await dataProvider.loadTransactions(
                    startDate: _startDate,
                    endDate: _endDate,
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'This Month',
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('This Month'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'Last Month',
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Last Month'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'This Year',
                  child: Row(
                    children: [
                      Icon(Icons.date_range_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('This Year'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'Custom',
                  child: Row(
                    children: [
                      Icon(Icons.edit_calendar_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Custom Period'),
                    ],
                  ),
                ),
              ],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedPeriod,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          final totalIncome = dataProvider.getTotalIncome(
            startDate: _startDate,
            endDate: _endDate,
          );
          final totalExpense = dataProvider.getTotalExpense(
            startDate: _startDate,
            endDate: _endDate,
          );
          final balance = totalIncome - totalExpense;
          
          final expensesByCategory = dataProvider.getExpensesByCategory(
            startDate: _startDate,
            endDate: _endDate,
          );

          // Calculate lend statistics
          final totalLendGiven = dataProvider.getTotalLendGiven();
          final totalLendTaken = dataProvider.getTotalLendTaken();

          // Calculate transaction counts
          final transactions = dataProvider.transactions.where((t) =>
            (_startDate == null || !t.date.isBefore(_startDate!)) &&
            (_endDate == null || !t.date.isAfter(_endDate!))).toList();
          
          final incomeTransactions = transactions.where((t) => 
            t.type == 'income' || t.type == 'lend_taken' || t.type == 'lend_returned_income').length;
          final expenseTransactions = transactions.where((t) => 
            t.type == 'expense' || t.type == 'lend_given' || t.type == 'lend_returned_expense').length;

          return RefreshIndicator(
            onRefresh: () => dataProvider.loadTransactions(
              startDate: _startDate,
              endDate: _endDate,
            ),
            child: ListView(
              padding: const EdgeInsets.all(20.0),
              children: [
                if (_startDate != null && _endDate != null)
                  _buildPeriodCard(_startDate!, _endDate!),
                const SizedBox(height: 16),
                _buildBalanceCard(balance),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Income',
                        totalIncome,
                        Icons.arrow_downward_rounded,
                        AppColors.income,
                        incomeTransactions,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Expense',
                        totalExpense,
                        Icons.arrow_upward_rounded,
                        AppColors.expense,
                        expenseTransactions,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildLendCard(
                        'To Receive',
                        totalLendGiven,
                        Icons.payments_outlined,
                        AppColors.income,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildLendCard(
                        'To Pay',
                        totalLendTaken,
                        Icons.account_balance_wallet_outlined,
                        AppColors.expense,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (dataProvider.spendingLimits.isNotEmpty) ...[
                  _buildSectionHeader('Spending Limits'),
                  const SizedBox(height: 16),
                  ..._buildSpendingLimitsList(dataProvider),
                  const SizedBox(height: 24),
                ],
                if (expensesByCategory.isNotEmpty) ...[
                  _buildSectionHeader('Expenses by Category'),
                  const SizedBox(height: 16),
                  _buildPieChartCard(expensesByCategory, dataProvider, totalExpense),
                  const SizedBox(height: 16),
                  ..._buildCategoryList(expensesByCategory, dataProvider, totalExpense),
                ] else
                  _buildEmptyState(),
                const SizedBox(height: 24),
                _buildInsightsCard(totalIncome, totalExpense, transactions.length),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPeriodCard(DateTime start, DateTime end) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.date_range_rounded, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Text(
            '${FormatUtils.formatShortDate(start)} - ${FormatUtils.formatShortDate(end)}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(double balance) {
    return Container(
      padding: const EdgeInsets.all(28.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            balance >= 0 ? 'Net Savings' : 'Net Loss',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            FormatUtils.formatCurrency(balance.abs()),
            style: TextStyle(
              color: balance >= 0 ? AppColors.success : AppColors.error,
              fontSize: 42,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, double amount, IconData icon, Color color, int count) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
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
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            FormatUtils.formatCurrency(amount),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count transactions',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLendCard(String title, double amount, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
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
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            FormatUtils.formatCurrency(amount),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPieChartCard(
    Map<int, double> expensesByCategory,
    DataProvider dataProvider,
    double totalExpense,
  ) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: SizedBox(
        height: 260,
        child: PieChart(
          PieChartData(
            sections: _buildPieChartSections(
              expensesByCategory,
              dataProvider,
            ),
            sectionsSpace: 4,
            centerSpaceRadius: 60,
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(
    Map<int, double> expensesByCategory,
    DataProvider dataProvider,
  ) {
    return expensesByCategory.entries.map((entry) {
      final index = expensesByCategory.keys.toList().indexOf(entry.key);
      final category = dataProvider.expenseCategories.firstWhere(
        (c) => c.id == entry.key,
        orElse: () => app_models.Category(name: 'Unknown', type: 'expense'),
      );
      
      return PieChartSectionData(
        color: _getColorForIndex(index),
        value: entry.value,
        title: category.name,
        radius: 90,
        titleStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<Widget> _buildCategoryList(
    Map<int, double> expensesByCategory,
    DataProvider dataProvider,
    double totalExpense,
  ) {
    return expensesByCategory.entries.map((entry) {
      final category = dataProvider.expenseCategories.firstWhere(
        (c) => c.id == entry.key,
        orElse: () => app_models.Category(name: 'Unknown', type: 'expense'),
      );
      final percentage = (entry.value / totalExpense * 100);

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getColorForIndex(
                  expensesByCategory.keys.toList().indexOf(entry.key),
                ),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${percentage.toStringAsFixed(1)}% of total',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              FormatUtils.formatCurrency(entry.value),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildInsightsCard(double income, double expense, int transactionCount) {
    final balance = income - expense;
    final savingsRate = income > 0 ? ((income - expense) / income * 100) : 0.0;
    final days = _endDate != null && _startDate != null 
        ? _endDate!.difference(_startDate!).inDays + 1 
        : 1;
    final avgDailyIncome = income / days;
    final avgDailyExpense = expense / days;
    final avgTransactionSize = transactionCount > 0 
        ? (income + expense) / transactionCount 
        : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.insights_rounded, color: AppColors.warning, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'Financial Insights',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildInsightRow('Net Balance', FormatUtils.formatCurrency(balance), 
              color: balance >= 0 ? AppColors.income : AppColors.expense),
          const Divider(height: 32),
          _buildInsightRow('Savings Rate', '${savingsRate.toStringAsFixed(1)}%',
              color: savingsRate >= 20 ? AppColors.success : savingsRate >= 10 ? AppColors.warning : AppColors.error),
          const Divider(height: 32),
          _buildInsightRow('Avg Daily Income', FormatUtils.formatCurrency(avgDailyIncome)),
          const Divider(height: 32),
          _buildInsightRow('Avg Daily Expense', FormatUtils.formatCurrency(avgDailyExpense)),
          const Divider(height: 32),
          _buildInsightRow('Total Transactions', transactionCount.toString()),
          const Divider(height: 32),
          _buildInsightRow('Avg Transaction Size', FormatUtils.formatCurrency(avgTransactionSize)),
          const Divider(height: 32),
          _buildInsightRow('Period', '$days days'),
        ],
      ),
    );
  }

  Widget _buildInsightRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSpendingLimitsList(DataProvider dataProvider) {
    return dataProvider.spendingLimits.map((limit) {
      // Calculate total spent across all categories in this limit
      double spent = 0.0;
      for (final categoryId in limit.categoryIds) {
        spent += dataProvider.getCategoryExpenses(
          categoryId: categoryId,
          startDate: _startDate,
          endDate: _endDate,
        );
      }
      
      final percentage = (spent / limit.limitAmount * 100).clamp(0.0, 100.0);
      final isOverLimit = spent > limit.limitAmount;
      final color = isOverLimit 
          ? AppColors.error 
          : percentage > 80 
              ? AppColors.warning 
              : AppColors.success;
      
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOverLimit 
                ? AppColors.error.withOpacity(0.3) 
                : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        limit.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${FormatUtils.formatCurrency(spent)} of ${FormatUtils.formatCurrency(limit.limitAmount)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (percentage / 100).clamp(0.0, 1.0),
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
            if (isOverLimit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_rounded, size: 16, color: AppColors.error),
                    const SizedBox(width: 6),
                    Text(
                      'Over budget by ${FormatUtils.formatCurrency(spent - limit.limitAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(48.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            'No expenses in this period',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColorForIndex(int index) {
    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.error,
      const Color(0xFF3B82F6),
      const Color(0xFF9C27B0),
      const Color(0xFFE91E63),
      const Color(0xFF00BCD4),
      const Color(0xFF8BC34A),
      const Color(0xFFFF9800),
    ];
    return colors[index % colors.length];
  }
}

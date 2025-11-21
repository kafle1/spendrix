import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/data_provider.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';
import '../models/transaction.dart' as model;
import 'add_transaction_screen.dart';
import 'reports_screen.dart';
import 'lend_borrow_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _isLendFeatureEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadLendFeatureSetting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DataProvider>(context, listen: false).loadAllData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLendFeatureSetting();
  }

  Future<void> _loadLendFeatureSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('isLendFeatureEnabled') ?? true;
    if (mounted && enabled != _isLendFeatureEnabled) {
      setState(() {
        _isLendFeatureEnabled = enabled;
        if (_selectedIndex == 2 && !enabled) {
          _selectedIndex = 0;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = _isLendFeatureEnabled
        ? [
            const DashboardScreen(),
            const ReportsScreen(),
            const LendBorrowScreen(),
            const SettingsScreen(),
          ]
        : [
            const DashboardScreen(),
            const ReportsScreen(),
            const SettingsScreen(),
          ];

    final List<NavigationDestination> destinations = _isLendFeatureEnabled
        ? const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.pie_chart_outline_rounded),
              selectedIcon: Icon(Icons.pie_chart_rounded),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz_rounded),
              selectedIcon: Icon(Icons.swap_horiz_rounded),
              label: 'Lend',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.pie_chart_outline_rounded),
              selectedIcon: Icon(Icons.pie_chart_rounded),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.02, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: screens[_selectedIndex],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddTransactionScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 24),
              label: const Text(
                'Transaction',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              heroTag: 'addTransaction',
              elevation: Theme.of(context).brightness == Brightness.dark ? 8 : 4,
              highlightElevation: Theme.of(context).brightness == Brightness.dark ? 12 : 6,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        elevation: 0,
        height: 65,
        backgroundColor: Theme.of(context).colorScheme.surface,
        destinations: destinations,
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isBalanceVisible = true;
  bool _showLending = true;
  bool _isLendFeatureEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadLendFeatureSetting();
    _loadDashboardLendingToggle();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLendFeatureSetting();
    _loadDashboardLendingToggle();
  }

  Future<void> _loadLendFeatureSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isLendFeatureEnabled = prefs.getBool('isLendFeatureEnabled') ?? true;
        // If lend feature is disabled globally, force _showLending to false
        if (!_isLendFeatureEnabled) {
          _showLending = false;
        }
      });
    }
  }

  Future<void> _loadDashboardLendingToggle() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      final savedToggleState = prefs.getBool('isDashboardLendingEnabled');
      setState(() {
        // Use saved state if available, otherwise default to true (enabled)
        // But only if the global feature is enabled
        if (_isLendFeatureEnabled) {
          _showLending = savedToggleState ?? true;
        }
      });
    }
  }

  Future<void> _saveDashboardLendingToggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDashboardLendingEnabled', value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Welcome back!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isBalanceVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            onPressed: () {
              setState(() {
                _isBalanceVisible = !_isBalanceVisible;
              });
            },
            tooltip: _isBalanceVisible ? 'Hide Balance' : 'Show Balance',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          final now = DateTime.now();
          final startOfMonth = DateTime(now.year, now.month, 1);
          final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

          // Calculate monthly income and expense, optionally excluding lending
          double monthlyIncome = 0;
          double monthlyExpense = 0;
          
          for (var transaction in dataProvider.transactions) {
            if (transaction.date.isBefore(startOfMonth) || transaction.date.isAfter(endOfMonth)) {
              continue;
            }
            
            if (transaction.type == 'income' || 
                (_showLending && (transaction.type == 'lend_taken' || transaction.type == 'lend_returned_income'))) {
              monthlyIncome += transaction.amount;
            } else if (transaction.type == 'expense' || 
                       (_showLending && (transaction.type == 'lend_given' || transaction.type == 'lend_returned_expense'))) {
              monthlyExpense += transaction.amount;
            }
          }

          final totalLendGiven = dataProvider.getTotalLendGiven();
          final totalLendTaken = dataProvider.getTotalLendTaken();

          return RefreshIndicator(
            onRefresh: () => dataProvider.loadAllData(),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
              children: [
                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: Theme.of(context).brightness == Brightness.dark
                          ? [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)]
                          : [AppColors.primary, AppColors.primary.withValues(alpha: 0.9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: Theme.of(context).brightness == Brightness.dark ? 16 : 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Balance',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha:0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Row(
                            children: [
                              if (_isLendFeatureEnabled)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha:0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.swap_horiz_rounded,
                                        color: Colors.white.withValues(alpha:0.7),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Lending',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha:0.7),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      SizedBox(
                                        height: 20,
                                        child: Switch(
                                          value: _showLending,
                                          onChanged: (value) {
                                            setState(() {
                                              _showLending = value;
                                            });
                                            _saveDashboardLendingToggle(value);
                                          },
                                          activeColor: AppColors.success,
                                          inactiveThumbColor: Colors.white.withValues(alpha:0.5),
                                          inactiveTrackColor: Colors.white.withValues(alpha:0.2),
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_isLendFeatureEnabled)
                                const SizedBox(width: 8),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isBalanceVisible
                            ? FormatUtils.formatCurrency(dataProvider.totalBalance)
                            : '••••••',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                      ),
                      if (_showLending && (totalLendGiven > 0 || totalLendTaken > 0)) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha:0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha:0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'To Receive',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha:0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isBalanceVisible
                                          ? FormatUtils.formatCurrency(totalLendGiven)
                                          : '••••••',
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: Colors.white.withValues(alpha:0.1),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'To Pay',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha:0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _isBalanceVisible
                                          ? FormatUtils.formatCurrency(totalLendTaken)
                                          : '••••••',
                                      style: const TextStyle(
                                        color: AppColors.error,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkSurface
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkBorder
                                : AppColors.border,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha:0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_downward_rounded,
                                    color: AppColors.success,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Income',
                                  style: TextStyle(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isBalanceVisible
                                  ? FormatUtils.formatCurrency(monthlyIncome)
                                  : '••••••',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkSurface
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkBorder
                                : AppColors.border,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha:0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_upward_rounded,
                                    color: AppColors.error,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Expense',
                                  style: TextStyle(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isBalanceVisible
                                  ? FormatUtils.formatCurrency(monthlyExpense)
                                  : '••••••',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                ...dataProvider.spendingLimits
                    .where((limit) => limit.isActive)
                    .map((limit) {
                  final spent = dataProvider.getSpendingForLimit(limit);
                  final percentage = (spent / limit.limitAmount * 100).clamp(0, 100);
                  
                  if (percentage < 70) return const SizedBox.shrink();
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: percentage >= 100
                          ? AppColors.error.withValues(alpha:0.1)
                          : AppColors.warning.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: percentage >= 100
                            ? AppColors.error.withValues(alpha:0.3)
                            : AppColors.warning.withValues(alpha:0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: percentage >= 100
                                    ? AppColors.error
                                    : AppColors.warning,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  limit.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: percentage >= 100
                                        ? AppColors.error
                                        : AppColors.warning,
                                  ),
                                ),
                              ),
                              Text(
                                '${percentage.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: percentage >= 100
                                      ? AppColors.error
                                      : AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: percentage / 100,
                              minHeight: 6,
                              backgroundColor: AppColors.surface.withValues(alpha:0.5),
                              color: percentage >= 100
                                  ? AppColors.error
                                  : AppColors.warning,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${FormatUtils.formatCurrency(spent)} of ${FormatUtils.formatCurrency(limit.limitAmount)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Accounts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Manage'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...dataProvider.accounts.map((account) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.2)
                              : Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.primary : AppColors.primary).withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.account_balance_wallet,
                          color: isDark ? AppColors.primary : AppColors.primary,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        account.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        account.type.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        ),
                      ),
                      trailing: Text(
                        _isBalanceVisible
                            ? FormatUtils.formatCurrency(account.balance)
                            : '••••••',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...dataProvider.transactions
                    .where((transaction) {
                      if (_showLending) return true;
                      // Exclude lending transactions when toggle is off
                      return transaction.type != 'lend_taken' &&
                             transaction.type != 'lend_given' &&
                             transaction.type != 'lend_returned_income' &&
                             transaction.type != 'lend_returned_expense';
                    })
                    .take(10)
                    .map((transaction) {
                  final account = dataProvider.accounts.firstWhere(
                    (a) => a.id == transaction.accountId,
                    orElse: () => Account(name: 'Unknown', balance: 0, type: 'other'),
                  );
                  
                  // Determine if transaction is income-type or expense-type
                  final isIncome = transaction.type == 'income' || 
                                   transaction.type == 'lend_taken' || 
                                   transaction.type == 'lend_returned_income';
                  
                  // Get display name for transaction
                  String displayName;
                  if (transaction.type == 'lend_taken') {
                    displayName = 'Lend Taken${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                  } else if (transaction.type == 'lend_given') {
                    displayName = 'Lend Given${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                  } else if (transaction.type == 'lend_returned_income') {
                    displayName = 'Lend Returned${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                  } else if (transaction.type == 'lend_returned_expense') {
                    displayName = 'Lend Returned${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                  } else {
                    final categories = isIncome
                        ? dataProvider.incomeCategories
                        : dataProvider.expenseCategories;
                    
                    final category = categories.firstWhere(
                      (c) => c.id == transaction.categoryId,
                      orElse: () => app_models.Category(name: 'Unknown', type: transaction.type),
                    );
                    displayName = category.name;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurface
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : AppColors.border,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isIncome
                              ? AppColors.income.withValues(alpha:0.1)
                              : AppColors.expense.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isIncome
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          color: isIncome
                              ? AppColors.income
                              : AppColors.expense,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${account.name} • ${FormatUtils.formatDate(transaction.date)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      trailing: Text(
                        _isBalanceVisible
                            ? '${isIncome ? '+' : '-'} ${FormatUtils.formatCurrency(transaction.amount)}'
                            : '••••••',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isIncome
                              ? AppColors.income
                              : AppColors.expense,
                        ),
                      ),
                      onTap: () {
                        _showTransactionDetails(context, transaction, account, app_models.Category(name: displayName, type: transaction.type));
                      },
                    ),
                  );
                }),
                if (dataProvider.transactions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurface
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No transactions yet',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkTextHint
                              : AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showTransactionDetails(
    BuildContext context,
    model.Transaction transaction,
    account,
    category,
  ) {
    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Transaction Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Amount'),
                  Text(
                    FormatUtils.formatCurrency(transaction.amount),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: transaction.type == 'income'
                          ? AppColors.income
                          : AppColors.expense,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildDetailRow('Type', transaction.type == 'income' ? 'Income' : 'Expense'),
              _buildDetailRow('Category', category.name),
              _buildDetailRow('Account', account.name),
              _buildDetailRow('Date', FormatUtils.formatDate(transaction.date)),
              if (transaction.remarks != null)
                _buildDetailRow('Remarks', transaction.remarks!),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Transaction'),
                            content: const Text(
                              'Are you sure you want to delete this transaction?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  dataProvider.deleteTransaction(transaction);
                                  Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextPrimary
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

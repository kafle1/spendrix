import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../models/spending_limit.dart';
import '../models/currency.dart';
import '../models/app_settings.dart';
import '../providers/data_provider.dart';
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';
import '../services/firebase_analytics_service.dart';
import '../services/data_export_service.dart';
import '../services/settings_service.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;
  Currency _selectedCurrency = SettingsService.currentCurrency;
  AppMode _selectedMode = SettingsService.currentAppMode;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _toggleThemeMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    setState(() => _isDarkMode = value);
    
    await FirebaseAnalyticsService.logThemeChanged(value ? 'dark' : 'light');
    
    if (!mounted) return;
    final updateTheme = Provider.of<Function(ThemeMode)>(context, listen: false);
    updateTheme(value ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _changeCurrency(Currency currency) async {
    await SettingsService.setCurrency(currency);
    setState(() => _selectedCurrency = currency);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Currency changed to ${currency.name}'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _changeAppMode(AppMode mode) async {
    await SettingsService.setAppMode(mode);
    setState(() => _selectedMode = mode);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('App mode changed to ${mode.displayName}'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
    
    // Navigate to home to refresh navigation
    Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
  }

  Future<void> _signOut() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/setup', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    final isLoggedIn = AuthService.currentUser != null;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // Appearance Section
          _buildSectionLabel('Appearance', isDark),
          _buildSettingTile(
            icon: _isDarkMode ? Icons.dark_mode : Icons.light_mode,
            title: 'Dark Mode',
            subtitle: 'Toggle dark theme',
            trailing: Switch(
              value: _isDarkMode,
              onChanged: _toggleThemeMode,
              activeColor: AppColors.primary,
            ),
            isDark: isDark,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          const SizedBox(height: 24),
          
          // App Settings Section
          _buildSectionLabel('App Settings', isDark),
          _buildSettingTile(
            icon: Icons.monetization_on_outlined,
            title: 'Currency',
            subtitle: '${_selectedCurrency.symbol} - ${_selectedCurrency.name}',
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showCurrencyPicker(),
            isDark: isDark,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          const SizedBox(height: 12),
          _buildSettingTile(
            icon: Icons.dashboard_customize_outlined,
            title: 'App Mode',
            subtitle: _selectedMode.displayName,
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showModePicker(),
            isDark: isDark,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          const SizedBox(height: 24),
          
          // Manage Section
          _buildSectionLabel('Manage', isDark),
          _buildSettingTile(
            icon: Icons.account_balance_wallet,
            title: 'Accounts',
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageAccountsScreen()),
            ),
            isDark: isDark,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          if (_selectedMode.hasExpenseTracking) ...[
            const SizedBox(height: 12),
            _buildSettingTile(
              icon: Icons.category,
              title: 'Categories',
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageCategoriesScreen()),
              ),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(height: 12),
            _buildSettingTile(
              icon: Icons.trending_up,
              title: 'Spending Limits',
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ManageSpendingLimitsScreen()),
              ),
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
          ],
          const SizedBox(height: 24),
          
          // Data Section
          _buildSectionLabel('Data & Backup', isDark),
          _buildSettingTile(
            icon: Icons.file_download_outlined,
            title: 'Export Data',
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _exportData(context),
            isDark: isDark,
            surfaceColor: surfaceColor,
            borderColor: borderColor,
          ),
          const SizedBox(height: 24),
          
          // Account Section
          if (isLoggedIn) ...[
            _buildSectionLabel('Account', isDark),
            _buildSettingTile(
              icon: Icons.logout,
              title: 'Sign Out',
              subtitle: AuthService.currentUser?.email,
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _signOut,
              isDark: isDark,
              surfaceColor: surfaceColor,
              borderColor: borderColor,
            ),
            const SizedBox(height: 24),
          ],
          
          // Danger Zone
          _buildSectionLabel('Danger Zone', isDark, isError: true),
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_forever, color: AppColors.error),
              ),
              title: const Text(
                'Reset All Data',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.error),
              ),
              subtitle: Text(
                'Delete all data and start fresh',
                style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
              onTap: () => _showResetConfirmation(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title, bool isDark, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isError ? AppColors.error : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    VoidCallback? onTap,
    required bool isDark,
    required Color surfaceColor,
    required Color borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : AppColors.primary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: isDark ? Colors.white : AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary))
            : null,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Select Currency', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: Currency.currencies.length,
                    itemBuilder: (context, index) {
                      final currency = Currency.currencies[index];
                      final isSelected = currency.code == _selectedCurrency.code;
                      return ListTile(
                        leading: Text(currency.symbol, style: const TextStyle(fontSize: 20)),
                        title: Text(currency.name),
                        subtitle: Text(currency.code),
                        trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.success) : null,
                        onTap: () {
                          Navigator.pop(context);
                          _changeCurrency(currency);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showModePicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select App Mode', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              ...AppMode.values.map((mode) {
                final isSelected = mode == _selectedMode;
                return ListTile(
                  leading: Icon(
                    mode == AppMode.expenseOnly ? Icons.receipt_long_outlined
                        : mode == AppMode.loanOnly ? Icons.swap_horiz_rounded
                        : Icons.account_balance_wallet_outlined,
                    color: isSelected ? AppColors.primary : null,
                  ),
                  title: Text(mode.displayName, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(mode.description),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: AppColors.success) : null,
                  onTap: () {
                    Navigator.pop(context);
                    if (mode != _selectedMode) _changeAppMode(mode);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showResetConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
            SizedBox(width: 12),
            Text('Reset All Data?'),
          ],
        ),
        content: const Text(
          'This will permanently delete:\n\n'
          '• All accounts and balances\n'
          '• All transactions\n'
          '• All categories\n'
          '• All loan records\n'
          '• All spending limits\n\n'
          'This action CANNOT be undone!',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      final dataProvider = Provider.of<DataProvider>(context, listen: false);
      await dataProvider.resetAllData();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setupCompleted', false);
      
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data has been reset'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating),
      );
      
      Navigator.pushNamedAndRemoveUntil(context, '/setup', (route) => false);
    }
  }

  Future<void> _exportData(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Preparing export...'), duration: Duration(seconds: 1)),
      );
      
      final dataProvider = Provider.of<DataProvider>(context, listen: false);
      await DataExportService.exportAndShare(dataProvider);
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }
}

class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Accounts'), elevation: 0),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAccountDialog(context),
        backgroundColor: isDark ? Colors.white : AppColors.primary,
        foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          if (dataProvider.accounts.isEmpty) {
            return const Center(child: Text('No accounts yet'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: dataProvider.accounts.length,
            itemBuilder: (context, index) {
              final account = dataProvider.accounts[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet, color: AppColors.primary),
                  ),
                  title: Text(account.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(FormatUtils.formatCurrency(account.balance)),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.error))),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditAccountDialog(context, account);
                      } else if (value == 'delete') {
                        _confirmDeleteAccount(context, account);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Account Name')),
            const SizedBox(height: 16),
            TextField(
              controller: balanceController,
              decoration: const InputDecoration(labelText: 'Initial Balance'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final balance = double.tryParse(balanceController.text) ?? 0;
              if (name.isEmpty) return;
              
              Provider.of<DataProvider>(context, listen: false).addAccount(
                Account(name: name, balance: balance, type: 'other'),
              );
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditAccountDialog(BuildContext context, Account account) {
    final nameController = TextEditingController(text: account.name);
    final balanceController = TextEditingController(text: account.balance.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Account Name')),
            const SizedBox(height: 16),
            TextField(
              controller: balanceController,
              decoration: const InputDecoration(labelText: 'Balance'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final balance = double.tryParse(balanceController.text) ?? account.balance;
              if (name.isEmpty) return;
              
              Provider.of<DataProvider>(context, listen: false).updateAccount(
                account.copyWith(name: name, balance: balance),
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, Account account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Are you sure you want to delete "${account.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (account.id != null) {
                Provider.of<DataProvider>(context, listen: false).deleteAccount(account.id!);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class ManageCategoriesScreen extends StatelessWidget {
  const ManageCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Categories'),
          elevation: 0,
          bottom: const TabBar(tabs: [Tab(text: 'Income'), Tab(text: 'Expense')]),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddCategoryDialog(context),
          child: const Icon(Icons.add),
        ),
        body: Consumer<DataProvider>(
          builder: (context, dataProvider, child) {
            return TabBarView(
              children: [
                _buildCategoryList(context, dataProvider.incomeCategories, 'income'),
                _buildCategoryList(context, dataProvider.expenseCategories, 'expense'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context, List<app_models.Category> categories, String type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (categories.isEmpty) {
      return Center(child: Text('No $type categories'));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (type == 'income' ? AppColors.income : AppColors.expense).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                color: type == 'income' ? AppColors.income : AppColors.expense,
              ),
            ),
            title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: () => _confirmDeleteCategory(context, category),
            ),
          ),
        );
      },
    );
  }

  void _showAddCategoryDialog(BuildContext context) {
    final controller = TextEditingController();
    String selectedType = 'income';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Category Name')),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'income', label: Text('Income')),
                  ButtonSegment(value: 'expense', label: Text('Expense')),
                ],
                selected: {selectedType},
                onSelectionChanged: (set) => setState(() => selectedType = set.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                
                Provider.of<DataProvider>(context, listen: false).addCategory(
                  app_models.Category(name: name, type: selectedType),
                );
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCategory(BuildContext context, app_models.Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text('Are you sure you want to delete "${category.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (category.id != null) {
                Provider.of<DataProvider>(context, listen: false).deleteCategory(category.id!);
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class ManageSpendingLimitsScreen extends StatelessWidget {
  const ManageSpendingLimitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(title: const Text('Spending Limits'), elevation: 0),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddLimitDialog(context),
        backgroundColor: isDark ? Colors.white : AppColors.primary,
        foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          if (dataProvider.spendingLimits.isEmpty) {
            return const Center(child: Text('No spending limits set'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: dataProvider.spendingLimits.length,
            itemBuilder: (context, index) {
              final limit = dataProvider.spendingLimits[index];
              final spent = dataProvider.getSpendingForLimit(limit);
              final percentage = (spent / limit.limitAmount * 100).clamp(0, 100);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(limit.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        Switch(
                          value: limit.isActive,
                          onChanged: (value) {
                            dataProvider.updateSpendingLimit(limit.copyWith(isActive: value));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        minHeight: 8,
                        backgroundColor: isDark ? AppColors.darkBorder : AppColors.border,
                        color: percentage >= 100 ? AppColors.error : (percentage >= 70 ? AppColors.warning : AppColors.success),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${FormatUtils.formatCurrency(spent)} of ${FormatUtils.formatCurrency(limit.limitAmount)}',
                      style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddLimitDialog(BuildContext context) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Spending Limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Limit Name')),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(labelText: 'Limit Amount'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final amount = double.tryParse(amountController.text) ?? 0;
              if (name.isEmpty || amount <= 0) return;
              
              Provider.of<DataProvider>(context, listen: false).addSpendingLimit(
                SpendingLimit(
                  name: name,
                  limitAmount: amount,
                  period: 'monthly',
                  accountIds: [],
                  categoryIds: [],
                  startDate: DateTime.now(),
                  isActive: true,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

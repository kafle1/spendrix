import 'package:flutter/material.dart'hide TextStyle, Colors, SizedBox, Padding, BorderRadius;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../models/spending_limit.dart';
import '../providers/data_provider.dart';
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';
import 'package:flutter/painting.dart' show TextStyle, BorderRadius;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart' show SizedBox, Padding;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;
  bool _isLendFeatureEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _loadLendFeatureSetting();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _loadLendFeatureSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLendFeatureEnabled = prefs.getBool('isLendFeatureEnabled') ?? true;
    });
  }

  Future<void> _toggleThemeMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    setState(() {
      _isDarkMode = value;
    });
    
    if (!mounted) return;
    final updateTheme = Provider.of<Function(ThemeMode)>(context, listen: false);
    updateTheme(value ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> _toggleLendFeature(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLendFeatureEnabled', value);
    setState(() {
      _isLendFeatureEnabled = value;
    });
    
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value 
            ? 'Lend & Borrow feature enabled' 
            : 'Lend & Borrow feature disabled'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? AppColors.darkBackground : AppColors.background;
    final surfaceColor = isDarkTheme ? AppColors.darkSurface : AppColors.surface;
    final borderColor = isDarkTheme ? AppColors.darkBorder : AppColors.border;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          Container(
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
                  color: (isDarkTheme ? Colors.white : AppColors.primary).withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  color: isDarkTheme ? Colors.white : AppColors.primary,
                ),
              ),
              title: const Text(
                'Dark Mode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Toggle dark theme',
                style: TextStyle(fontSize: 12, color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary),
              ),
              trailing: Switch(
                value: _isDarkMode,
                onChanged: _toggleThemeMode,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                inactiveThumbColor: isDarkTheme ? Colors.grey[400] : Colors.grey[300],
                inactiveTrackColor: isDarkTheme ? Colors.grey[700] : Colors.grey[300],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
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
                  color: (isDarkTheme ? Colors.white : AppColors.primary).withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.payments_outlined,
                  color: isDarkTheme ? Colors.white : AppColors.primary,
                ),
              ),
              title: const Text(
                'Lend & Borrow',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Enable lend and borrow tracking',
                style: TextStyle(fontSize: 12, color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary),
              ),
              trailing: Switch(
                value: _isLendFeatureEnabled,
                onChanged: _toggleLendFeature,
                activeColor: AppColors.primary,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                inactiveThumbColor: isDarkTheme ? Colors.grey[400] : Colors.grey[300],
                inactiveTrackColor: isDarkTheme ? Colors.grey[700] : Colors.grey[300],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Text(
              'Manage',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
            ),
          ),
          _buildSectionHeader(
            'Accounts',
            Icons.account_balance_wallet,
            context,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ManageAccountsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSectionHeader(
            'Categories',
            Icons.category,
            context,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ManageCategoriesScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildSectionHeader(
            'Spending Limits',
            Icons.trending_up,
            context,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ManageSpendingLimitsScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Text(
              'Danger Zone',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.error.withValues(alpha:0.2)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_forever,
                  color: AppColors.error,
                ),
              ),
              title: const Text(
                'Reset All Data',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
              subtitle: Text(
                'Delete all accounts, transactions, and settings',
                style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkTextSecondary : AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.error),
              onTap: () => _showResetConfirmation(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, BuildContext context, VoidCallback onTap) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDarkTheme ? AppColors.darkSurface : AppColors.surface;
    final borderColor = isDarkTheme ? AppColors.darkBorder : AppColors.border;
    
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
            color: (isDarkTheme ? Colors.white : AppColors.primary).withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: isDarkTheme ? Colors.white : AppColors.primary),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary),
        onTap: onTap,
      ),
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
          '• All lend/borrow records\n'
          '• All spending limits\n\n'
          'This action CANNOT be undone!',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reset Everything'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (!context.mounted) return;
      final dataProvider = Provider.of<DataProvider>(context, listen: false);
      await dataProvider.resetAllData();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isFirstTime', true);
      
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All data has been reset successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      Navigator.pushNamedAndRemoveUntil(context, '/setup', (route) => false);
    }
  }
}

class ManageAccountsScreen extends StatelessWidget {
  const ManageAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Accounts'),
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
          final surfaceColor = isDarkTheme ? AppColors.darkSurface : AppColors.surface;
          final borderColor = isDarkTheme ? AppColors.darkBorder : AppColors.border;
          
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              ...dataProvider.accounts.map((account) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: (isDarkTheme ? Colors.white : AppColors.primary).withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.account_balance_wallet, color: isDarkTheme ? Colors.white : AppColors.primary),
                    ),
                    title: Text(
                      account.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDarkTheme ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      FormatUtils.formatCurrency(account.balance),
                      style: TextStyle(
                        color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showEditAccountDialog(context, account, dataProvider),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.error),
                          onPressed: () => _confirmDeleteAccount(context, account, dataProvider),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddAccountDialog(context, dataProvider),
                icon: const Icon(Icons.add),
                label: const Text('Add Account'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context, DataProvider dataProvider) {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Account Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Initial Balance',
                  prefixText: 'Rs ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                
                await dataProvider.addAccount(Account(
                  name: nameController.text,
                  balance: double.tryParse(balanceController.text) ?? 0,
                  type: 'other',
                ));
                
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showEditAccountDialog(BuildContext context, Account account, DataProvider dataProvider) {
    final nameController = TextEditingController(text: account.name);
    final balanceController = TextEditingController(text: account.balance.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Account Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Balance',
                  prefixText: 'Rs ',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                
                await dataProvider.updateAccount(account.copyWith(
                  name: nameController.text,
                  balance: double.tryParse(balanceController.text) ?? account.balance,
                ));
                
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context, Account account, DataProvider dataProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account'),
          content: Text('Are you sure you want to delete ${account.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await dataProvider.deleteAccount(account.id!);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
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
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Income'),
              Tab(text: 'Expense'),
            ],
          ),
        ),
        body: Consumer<DataProvider>(
          builder: (context, dataProvider, child) {
            return TabBarView(
              children: [
                _buildCategoryList(context, dataProvider, 'income'),
                _buildCategoryList(context, dataProvider, 'expense'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context, DataProvider dataProvider, String type) {
    final categories = type == 'income'
        ? dataProvider.incomeCategories
        : dataProvider.expenseCategories;

    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDarkTheme ? AppColors.darkSurface : AppColors.surface;
    final borderColor = isDarkTheme ? AppColors.darkBorder : AppColors.border;

    return Column(
      children: [
        Expanded(
          child: ReorderableListView(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.all(16.0),
            onReorder: (oldIndex, newIndex) async {
              // Adjust newIndex if moving item down the list
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              
              // Create new list with reordered categories
              final items = List<app_models.Category>.from(categories);
              final item = items.removeAt(oldIndex);
              items.insert(newIndex, item);
              
              // Update the order in the database
              await dataProvider.reorderCategories(items);
            },
            children: categories.map((category) {
              return Container(
                key: ValueKey(category.id),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: categories.indexOf(category),
                        child: Icon(
                          Icons.drag_indicator,
                          color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: type == 'income'
                              ? AppColors.income.withValues(alpha:0.1)
                              : AppColors.expense.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          type == 'income' ? Icons.arrow_downward : Icons.arrow_upward,
                          color: type == 'income' ? AppColors.income : AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    category.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDarkTheme ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _showEditCategoryDialog(context, category, dataProvider, type),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () => _confirmDeleteCategory(context, category, dataProvider),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAddCategoryDialog(context, dataProvider, type),
              icon: const Icon(Icons.add),
              label: Text('Add ${type == 'income' ? 'Income' : 'Expense'} Category'),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddCategoryDialog(BuildContext context, DataProvider dataProvider, String type) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add ${type == 'income' ? 'Income' : 'Expense'} Category'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Category Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                
                await dataProvider.addCategory(app_models.Category(
                  name: nameController.text,
                  type: type,
                ));
                
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showEditCategoryDialog(BuildContext context, app_models.Category category, DataProvider dataProvider, String type) {
    final nameController = TextEditingController(text: category.name);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit ${type == 'income' ? 'Income' : 'Expense'} Category'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Category Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty) return;
                if (nameController.text == category.name) {
                  Navigator.pop(context);
                  return;
                }
                
                await dataProvider.updateCategory(category.copyWith(
                  name: nameController.text,
                ));
                
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteCategory(BuildContext context, app_models.Category category, DataProvider dataProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Category'),
          content: Text('Are you sure you want to delete ${category.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await dataProvider.deleteCategory(category.id!);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class ManageSpendingLimitsScreen extends StatelessWidget {
  const ManageSpendingLimitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Limits'),
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          final limits = dataProvider.spendingLimits;
          final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
          final surfaceColor = isDarkTheme ? AppColors.darkSurface : AppColors.surface;
          final borderColor = isDarkTheme ? AppColors.darkBorder : AppColors.border;
          final backgroundColor = isDarkTheme ? AppColors.darkBackground : AppColors.background;
          
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              ...limits.map((limit) {
                final spent = dataProvider.getSpendingForLimit(limit);
                final percentage = (spent / limit.limitAmount * 100).clamp(0, 100);
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              limit.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDarkTheme ? AppColors.darkTextPrimary : AppColors.textPrimary,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditLimitDialog(context, limit, dataProvider),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                                  onPressed: () => _confirmDeleteLimit(context, limit, dataProvider),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${FormatUtils.formatCurrency(spent)} of ${FormatUtils.formatCurrency(limit.limitAmount)}',
                          style: TextStyle(
                            color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percentage / 100,
                            minHeight: 8,
                            backgroundColor: backgroundColor,
                            color: percentage > 90
                                ? AppColors.error
                                : percentage > 70
                                    ? AppColors.warning
                                    : AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${percentage.toStringAsFixed(0)}% used • ${limit.period}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (limits.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'No spending limits set',
                        style: TextStyle(
                          color: isDarkTheme ? AppColors.darkTextHint : AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddLimitDialog(context, dataProvider),
                icon: const Icon(Icons.add),
                label: const Text('Add Spending Limit'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddLimitDialog(BuildContext context, DataProvider dataProvider) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    String selectedPeriod = 'monthly';
    List<int> selectedAccounts = dataProvider.accounts.map((a) => a.id!).toList();
    List<int> selectedCategories = dataProvider.expenseCategories.map((c) => c.id!).toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Spending Limit'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Limit Name'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Limit Amount',
                        prefixText: 'Rs ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedPeriod,
                      decoration: const InputDecoration(labelText: 'Period'),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                        DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedPeriod = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Accounts:'),
                    ...dataProvider.accounts.map((account) {
                      return CheckboxListTile(
                        title: Text(account.name),
                        value: selectedAccounts.contains(account.id),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value!) {
                              selectedAccounts.add(account.id!);
                            } else {
                              selectedAccounts.remove(account.id);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text('Select Categories:'),
                    ...dataProvider.expenseCategories.map((category) {
                      return CheckboxListTile(
                        title: Text(category.name),
                        value: selectedCategories.contains(category.id),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value!) {
                              selectedCategories.add(category.id!);
                            } else {
                              selectedCategories.remove(category.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        amountController.text.isEmpty ||
                        selectedAccounts.isEmpty ||
                        selectedCategories.isEmpty) {
                      return;
                    }
                    
                    await dataProvider.addSpendingLimit(SpendingLimit(
                      name: nameController.text,
                      limitAmount: double.parse(amountController.text),
                      period: selectedPeriod,
                      accountIds: selectedAccounts,
                      categoryIds: selectedCategories,
                      startDate: DateTime.now(),
                    ));
                    
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditLimitDialog(BuildContext context, SpendingLimit limit, DataProvider dataProvider) {
    final nameController = TextEditingController(text: limit.name);
    final amountController = TextEditingController(text: limit.limitAmount.toString());
    String selectedPeriod = limit.period;
    List<int> selectedAccounts = List.from(limit.accountIds);
    List<int> selectedCategories = List.from(limit.categoryIds);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Spending Limit'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Limit Name'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Limit Amount',
                        prefixText: 'Rs ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedPeriod,
                      decoration: const InputDecoration(labelText: 'Period'),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                        DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedPeriod = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('Select Accounts:'),
                    ...dataProvider.accounts.map((account) {
                      return CheckboxListTile(
                        title: Text(account.name),
                        value: selectedAccounts.contains(account.id),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value!) {
                              selectedAccounts.add(account.id!);
                            } else {
                              selectedAccounts.remove(account.id);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text('Select Categories:'),
                    ...dataProvider.expenseCategories.map((category) {
                      return CheckboxListTile(
                        title: Text(category.name),
                        value: selectedCategories.contains(category.id),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value!) {
                              selectedCategories.add(category.id!);
                            } else {
                              selectedCategories.remove(category.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        amountController.text.isEmpty ||
                        selectedAccounts.isEmpty ||
                        selectedCategories.isEmpty) {
                      return;
                    }
                    
                    await dataProvider.updateSpendingLimit(limit.copyWith(
                      name: nameController.text,
                      limitAmount: double.parse(amountController.text),
                      period: selectedPeriod,
                      accountIds: selectedAccounts,
                      categoryIds: selectedCategories,
                    ));
                    
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteLimit(BuildContext context, SpendingLimit limit, DataProvider dataProvider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Spending Limit'),
          content: Text('Are you sure you want to delete ${limit.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await dataProvider.deleteSpendingLimit(limit.id!);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

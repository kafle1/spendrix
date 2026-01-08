import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../models/lend_record.dart';
import '../models/currency.dart';
import '../models/app_settings.dart';
import '../providers/data_provider.dart';
import '../services/settings_service.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late TabController _lendTabController;
  int _currentPage = 0;

  final List<Map<String, dynamic>> _accounts = [];
  final List<Map<String, dynamic>> _incomeCategories = [];
  final List<Map<String, dynamic>> _expenseCategories = [];
  final List<Map<String, dynamic>> _lendGivenRecords = [];
  final List<Map<String, dynamic>> _lendTakenRecords = [];
  
  AppMode _selectedMode = AppMode.both;
  Currency _selectedCurrency = Currency.currencies.first;

  @override
  void initState() {
    super.initState();
    _lendTabController = TabController(length: 2, vsync: this);
    _initializeDefaultData();
  }

  void _initializeDefaultData() {
    _accounts.add({
      'name': 'Cash',
      'balance': 0.0,
      'type': 'cash',
    });

    _incomeCategories.add({'name': 'Salary'});

    _expenseCategories.addAll([
      {'name': 'Food'},
      {'name': 'Entertainment'},
      {'name': 'Others'},
    ]);
  }

  int get _totalPages {
    if (_selectedMode == AppMode.loanOnly) {
      return 3; // Mode + Currency, Lend Records, Accounts
    } else if (_selectedMode == AppMode.expenseOnly) {
      return 4; // Mode + Currency, Accounts, Income, Expense
    }
    return 5; // Mode + Currency, Lend Records, Accounts, Income, Expense
  }

  List<Widget> get _pages {
    final pages = <Widget>[_buildModeSelectionPage()];
    
    if (_selectedMode.hasLoanTracking) {
      pages.add(_buildLendRecordsPage());
    }
    
    pages.add(_buildAccountsPage());
    
    if (_selectedMode.hasExpenseTracking) {
      pages.add(_buildIncomeCategoriesPage());
      pages.add(_buildExpenseCategoriesPage());
    }
    
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (index) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 40 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.primary
                          : (isDark ? AppColors.darkBorder : AppColors.divider),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: _pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _handleBack,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                          side: BorderSide(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkBorder
                                : AppColors.border,
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLastPage ? _completeSetup : _handleNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.white 
                            : AppColors.primary,
                        foregroundColor: Theme.of(context).brightness == Brightness.dark 
                            ? AppColors.darkBackground 
                            : Colors.white,
                      ),
                      child: Text(_isLastPage ? 'Get Started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isLastPage => _currentPage == _totalPages - 1;

  void _handleNext() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _handleBack() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildModeSelectionPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your Mode',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select how you want to use Spendrix',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _buildModeOption(
            AppMode.expenseOnly,
            Icons.receipt_long_outlined,
            AppColors.success,
          ),
          const SizedBox(height: 12),
          _buildModeOption(
            AppMode.loanOnly,
            Icons.swap_horiz_rounded,
            AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildModeOption(
            AppMode.both,
            Icons.account_balance_wallet_outlined,
            AppColors.warning,
          ),
          const SizedBox(height: 32),
          Text(
            'Select Currency',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
            child: DropdownButtonFormField<Currency>(
              value: _selectedCurrency,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.monetization_on_outlined),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              items: Currency.currencies.map((currency) {
                return DropdownMenuItem(
                  value: currency,
                  child: Text('${currency.symbol} - ${currency.name} (${currency.code})'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedCurrency = value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeOption(AppMode mode, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedMode == mode;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMode = mode;
          if (!mode.hasLoanTracking) {
            _lendGivenRecords.clear();
            _lendTakenRecords.clear();
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected 
              ? color.withValues(alpha: 0.1) 
              : (isDark ? AppColors.darkSurface : AppColors.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.displayName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLendRecordsPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Initial Loan Records',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add existing loans (optional)',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TabBar(
          controller: _lendTabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'I Gave'),
            Tab(text: 'I Took'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _lendTabController,
            children: [
              _buildLendRecordsList('given'),
              _buildLendRecordsList('taken'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLendRecordsList(String type) {
    final records = type == 'given' ? _lendGivenRecords : _lendTakenRecords;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          if (records.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    type == 'given' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    type == 'given' ? 'No money lent yet' : 'No money borrowed yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can skip this step',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? AppColors.darkTextHint : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            )
          else
            ...records.asMap().entries.map((entry) {
              final index = entry.key;
              final record = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (type == 'given' ? AppColors.expense : AppColors.income)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          type == 'given' ? Icons.arrow_upward : Icons.arrow_downward,
                          color: type == 'given' ? AppColors.expense : AppColors.income,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record['personName'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_selectedCurrency.symbol} ${record['amount'].toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: type == 'given' ? AppColors.expense : AppColors.income,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: AppColors.error,
                        onPressed: () {
                          setState(() => records.removeAt(index));
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _showAddLendRecordDialog(type),
            icon: const Icon(Icons.add),
            label: Text(type == 'given' ? 'Add Lent Record' : 'Add Borrowed Record'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
              foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddLendRecordDialog(String type) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final remarksController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(type == 'given' ? 'Add Lent Record' : 'Add Borrowed Record'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Person Name',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        prefixText: '${_selectedCurrency.symbol} ',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarksController,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final amount = double.tryParse(amountController.text.trim());

                    if (name.isEmpty || amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter valid details')),
                      );
                      return;
                    }

                    setState(() {
                      final record = {
                        'personName': name,
                        'amount': amount,
                        'date': selectedDate,
                        'remarks': remarksController.text.trim(),
                      };
                      if (type == 'given') {
                        _lendGivenRecords.add(record);
                      } else {
                        _lendTakenRecords.add(record);
                      }
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAccountsPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Setup Your Accounts',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add accounts and set initial balances',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          ..._accounts.asMap().entries.map((entry) {
            final index = entry.key;
            final account = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: account['name'],
                            decoration: const InputDecoration(
                              labelText: 'Account Name',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(12)),
                              ),
                            ),
                            onChanged: (value) => _accounts[index]['name'] = value,
                          ),
                        ),
                        if (_accounts.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: AppColors.error,
                            onPressed: () => setState(() => _accounts.removeAt(index)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: account['balance'].toString(),
                      decoration: InputDecoration(
                        labelText: 'Initial Balance',
                        prefixText: '${_selectedCurrency.symbol} ',
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (value) {
                        _accounts[index]['balance'] = double.tryParse(value) ?? 0.0;
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _accounts.add({'name': 'New Account', 'balance': 0.0, 'type': 'other'});
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Account'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
              foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeCategoriesPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Income Categories',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Customize your income sources',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _incomeCategories.asMap().entries.map((entry) {
              final index = entry.key;
              final category = entry.value;
              return InputChip(
                label: Text(category['name']),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => setState(() => _incomeCategories.removeAt(index)),
                backgroundColor: AppColors.income.withValues(alpha: 0.1),
                side: BorderSide(color: AppColors.income.withValues(alpha: 0.3)),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showAddCategoryDialog('income'),
            icon: const Icon(Icons.add),
            label: const Text('Add Income Category'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
              foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCategoriesPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Expense Categories',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Customize your expense categories',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _expenseCategories.asMap().entries.map((entry) {
              final index = entry.key;
              final category = entry.value;
              return InputChip(
                label: Text(category['name']),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => setState(() => _expenseCategories.removeAt(index)),
                backgroundColor: AppColors.expense.withValues(alpha: 0.1),
                side: BorderSide(color: AppColors.expense.withValues(alpha: 0.3)),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showAddCategoryDialog('expense'),
            icon: const Icon(Icons.add),
            label: const Text('Add Expense Category'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
              foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog(String type) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add ${type == 'income' ? 'Income' : 'Expense'} Category'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Category Name'),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                
                setState(() {
                  if (type == 'income') {
                    _incomeCategories.add({'name': name});
                  } else {
                    _expenseCategories.add({'name': name});
                  }
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _completeSetup() async {
    for (var accountData in _accounts) {
      if (accountData['name'].toString().trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter valid account names')),
        );
        return;
      }
    }

    await SettingsService.setCurrency(_selectedCurrency);
    await SettingsService.setAppMode(_selectedMode);

    if (!mounted) return;
    
    final dataProvider = Provider.of<DataProvider>(context, listen: false);

    for (var accountData in _accounts) {
      await dataProvider.addAccount(Account(
        name: accountData['name'],
        balance: accountData['balance'],
        type: accountData['type'],
      ));
    }

    if (_selectedMode.hasExpenseTracking) {
      for (var categoryData in _incomeCategories) {
        await dataProvider.addCategory(app_models.Category(
          name: categoryData['name'],
          type: 'income',
        ));
      }

      for (var categoryData in _expenseCategories) {
        await dataProvider.addCategory(app_models.Category(
          name: categoryData['name'],
          type: 'expense',
        ));
      }
    }

    if (_selectedMode.hasLoanTracking) {
      for (var record in _lendGivenRecords) {
        await dataProvider.addLendRecord(LendRecord(
          type: 'given',
          personName: record['personName'],
          amount: record['amount'],
          date: record['date'],
          remarks: record['remarks'].isEmpty ? null : record['remarks'],
          isSettled: false,
        ));
      }

      for (var record in _lendTakenRecords) {
        await dataProvider.addLendRecord(LendRecord(
          type: 'taken',
          personName: record['personName'],
          amount: record['amount'],
          date: record['date'],
          remarks: record['remarks'].isEmpty ? null : record['remarks'],
          isSettled: false,
        ));
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setupCompleted', true);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _lendTabController.dispose();
    super.dispose();
  }
}

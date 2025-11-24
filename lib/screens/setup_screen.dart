import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../models/lend_record.dart';
import '../providers/data_provider.dart';
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
  bool _enableLendBorrow = false;

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

  int _getDisplayPageIndex(int actualPage) {
    if (!_enableLendBorrow && actualPage >= 1) {
      return actualPage - 1;
    }
    return actualPage;
  }

  int get _totalPages => _enableLendBorrow ? 5 : 4;

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
                    width: _getDisplayPageIndex(_currentPage) == index ? 40 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _getDisplayPageIndex(_currentPage) == index
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
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildLendBorrowTogglePage(),
                  if (_enableLendBorrow) _buildLendRecordsPage(),
                  _buildAccountsPage(),
                  _buildIncomeCategoriesPage(),
                  _buildExpenseCategoriesPage(),
                ],
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
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: Theme.of(context).brightness == Brightness.dark ? 4 : 2,
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

  bool get _isLastPage {
    if (_enableLendBorrow) {
      return _currentPage == 4;
    } else {
      return _currentPage == 3;
    }
  }

  void _handleNext() {
    if (_currentPage == 0 && !_enableLendBorrow) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _handleBack() {
    if (_currentPage == 1 && !_enableLendBorrow) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  Widget _buildLendBorrowTogglePage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lend & Borrow',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Track money lent to others or borrowed from them',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.swap_horiz,
                          color: AppColors.primary,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Lend & Borrow',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _enableLendBorrow ? 'Enabled' : 'Disabled',
                              style: TextStyle(
                                fontSize: 14,
                                color: _enableLendBorrow
                                    ? AppColors.success
                                    : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enableLendBorrow,
                        onChanged: (value) {
                          setState(() {
                            _enableLendBorrow = value;
                            if (!value) {
                              _lendGivenRecords.clear();
                              _lendTakenRecords.clear();
                            }
                          });
                        },
                        activeColor: AppColors.primary,
                        activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                        inactiveThumbColor: isDark ? Colors.grey[400] : Colors.grey[300],
                        inactiveTrackColor: isDark ? Colors.grey[700] : Colors.grey[300],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),
                  _buildFeatureItem(
                    Icons.person_add_outlined,
                    'Track Lent Money',
                    'Keep record of money you\'ve lent to others',
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem(
                    Icons.person_outline,
                    'Track Borrowed Money',
                    'Keep record of money you\'ve borrowed',
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem(
                    Icons.account_balance_wallet_outlined,
                    'Separate Balance View',
                    'See liquid vs non-liquid money',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
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
                'Initial Lend Records',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add existing lends and borrows',
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
            Tab(text: 'Lent to Others'),
            Tab(text: 'Borrowed'),
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
                    type == 'given' ? Icons.person_add_outlined : Icons.person_outline,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    type == 'given' ? 'No lent records yet' : 'No borrowed records yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
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
                              'Rs ${record['amount'].toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: type == 'given' ? AppColors.expense : AppColors.income,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (record['remarks'] != null && record['remarks'].isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  record['remarks'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        color: AppColors.error,
                        onPressed: () {
                          setState(() {
                            records.removeAt(index);
                          });
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
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: 'Rs ',
                        border: OutlineInputBorder(),
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
                          if (picked != null) {
                            setDialogState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.textPrimary,
                            ),
                          ),
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

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter person name')),
                      );
                      return;
                    }

                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter valid amount')),
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
            'Add your accounts and set initial balances',
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
                            onChanged: (value) {
                              _accounts[index]['name'] = value;
                            },
                          ),
                        ),
                        if (_accounts.length > 1)
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: AppColors.error,
                            onPressed: () {
                              setState(() {
                                _accounts.removeAt(index);
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: account['balance'].toString(),
                      decoration: const InputDecoration(
                        labelText: 'Initial Balance',
                        prefixText: 'Rs ',
                        border: OutlineInputBorder(
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
                _accounts.add({
                  'name': 'New Account',
                  'balance': 0.0,
                  'type': 'other',
                });
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
                onDeleted: () {
                  setState(() {
                    _incomeCategories.removeAt(index);
                  });
                },
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
                onDeleted: () {
                  setState(() {
                    _expenseCategories.removeAt(index);
                  });
                },
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
            decoration: const InputDecoration(
              labelText: 'Category Name',
            ),
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
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter category name')),
                  );
                  return;
                }
                
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

    final dataProvider = Provider.of<DataProvider>(context, listen: false);

    for (var accountData in _accounts) {
      await dataProvider.addAccount(Account(
        name: accountData['name'],
        balance: accountData['balance'],
        type: accountData['type'],
      ));
    }

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

    if (_enableLendBorrow) {
      // Save initial lend records (these are existing debts, not new transactions)
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
    await prefs.setBool('isLendFeatureEnabled', _enableLendBorrow);
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

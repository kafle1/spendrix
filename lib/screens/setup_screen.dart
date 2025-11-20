import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../providers/data_provider.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _accounts = [];
  final List<Map<String, dynamic>> _incomeCategories = [];
  final List<Map<String, dynamic>> _expenseCategories = [];
  bool _enableLendBorrow = false;

  @override
  void initState() {
    super.initState();
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
                children: List.generate(4, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 40 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _currentPage == index 
                          ? AppColors.primary 
                          : AppColors.divider,
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
                  _buildAccountsPage(),
                  _buildLendBorrowTogglePage(),
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
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutCubic,
                          );
                        },
                        child: const Text('Back'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _currentPage < 3
                          ? () {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeInOutCubic,
                              );
                            }
                          : _completeSetup,
                      child: Text(_currentPage < 3 ? 'Next' : 'Get Started'),
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

  Widget _buildAccountsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Setup Your Accounts',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your accounts and set initial balances',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          ..._accounts.asMap().entries.map((entry) {
            final index = entry.key;
            final account = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
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
                  'type': 'other'
                });
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Account'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              minimumSize: const Size(double.infinity, 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLendBorrowTogglePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lend & Borrow',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Track money lent to others or borrowed from them',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
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
                            color: AppColors.primary.withOpacity(0.1),
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
                            const Text(
                              'Enable Lend & Borrow',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _enableLendBorrow ? 'Enabled' : 'Disabled',
                              style: TextStyle(
                                fontSize: 14,
                                color: _enableLendBorrow ? AppColors.success : AppColors.textSecondary,
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
                          });
                        },
                        activeColor: AppColors.primary,
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

  Widget _buildIncomeCategoriesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Income Categories',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Customize your income sources',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _incomeCategories.asMap().entries.map((entry) {
              final index = entry.key;
              final category = entry.value;
              final isLendCategory = category['name'] == 'Lend Returned';
              return InputChip(
                label: Text(category['name']),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: isLendCategory
                    ? null
                    : () {
                        setState(() {
                          _incomeCategories.removeAt(index);
                        });
                      },
                backgroundColor: AppColors.income.withOpacity(0.1),
                side: BorderSide(color: AppColors.income.withOpacity(0.3)),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseCategoriesPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Expense Categories',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Customize your expense categories',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _expenseCategories.asMap().entries.map((entry) {
              final index = entry.key;
              final category = entry.value;
              final isLendCategory = category['name'] == 'Lend Given';
              return InputChip(
                label: Text(category['name']),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: isLendCategory
                    ? null
                    : () {
                        setState(() {
                          _expenseCategories.removeAt(index);
                        });
                      },
                backgroundColor: AppColors.expense.withOpacity(0.1),
                side: BorderSide(color: AppColors.expense.withOpacity(0.3)),
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
            ),
          ),
        ],
      ),
    );
  }

  void _showAddCategoryDialog(String type) {
    final TextEditingController controller = TextEditingController();
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
                if (controller.text.trim().isNotEmpty) {
                  setState(() {
                    if (type == 'income') {
                      _incomeCategories.add({'name': controller.text.trim()});
                    } else {
                      _expenseCategories.add({'name': controller.text.trim()});
                    }
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _completeSetup() async {
    final dataProvider = Provider.of<DataProvider>(context, listen: false);

    if (_enableLendBorrow) {
      if (!_incomeCategories.any((cat) => cat['name'] == 'Lend Returned')) {
        _incomeCategories.add({'name': 'Lend Returned'});
      }
      if (!_expenseCategories.any((cat) => cat['name'] == 'Lend Given')) {
        _expenseCategories.add({'name': 'Lend Given'});
      }
    }

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lendBorrowEnabled', _enableLendBorrow);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

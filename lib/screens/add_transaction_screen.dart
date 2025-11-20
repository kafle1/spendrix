import 'package:flutter/material.dart' hide TextStyle, Colors, BorderRadius;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart' as model;
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../providers/data_provider.dart';
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';
import 'package:flutter/painting.dart' show TextStyle, BorderRadius;
import 'package:flutter/material.dart' show Colors;

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _remarksController = TextEditingController();
  final _personNameController = TextEditingController();

  String _selectedType = 'expense';
  String? _selectedLendType;
  Account? _selectedAccount;
  app_models.Category? _selectedCategory;
  DateTime _selectedDate = DateTime.now();
  String? _selectedPerson;
  bool _isLendFeatureEnabled = true;

  bool get _isLendTransaction => _selectedLendType != null;

  @override
  void initState() {
    super.initState();
    _loadLendFeatureSetting();
  }

  Future<void> _loadLendFeatureSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLendFeatureEnabled = prefs.getBool('isLendFeatureEnabled') ?? true;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarksController.dispose();
    _personNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark 
          ? AppColors.darkBackground 
          : AppColors.background,
      appBar: AppBar(
        title: const Text('Add Transaction'),
        elevation: 0,
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          if (dataProvider.accounts.isEmpty) {
            return _buildEmptyState();
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildTypeSelection(),
                const SizedBox(height: 16),
                if (_isLendTransaction) ...[
                  _buildPersonSelection(dataProvider),
                  const SizedBox(height: 16),
                ],
                _buildAmountCard(),
                const SizedBox(height: 16),
                _buildAccountCard(dataProvider),
                const SizedBox(height: 16),
                if (!_isLendTransaction) ...[
                  _buildCategoryCard(dataProvider),
                  const SizedBox(height: 16),
                ],
                _buildDateCard(),
                const SizedBox(height: 16),
                _buildRemarksCard(),
                const SizedBox(height: 24),
                _buildSaveButton(),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(height: 24),
          Text(
            'No accounts available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please add an account first',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeSelection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transaction Type',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTypeButton(
                  'Income',
                  'income',
                  Icons.arrow_downward_rounded,
                  AppColors.income,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTypeButton(
                  'Expense',
                  'expense',
                  Icons.arrow_upward_rounded,
                  AppColors.expense,
                ),
              ),
            ],
          ),
          if (_isLendFeatureEnabled && _selectedType == 'income') ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Lend Options',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildLendOption(
              'Lend Taken',
              'I borrowed money from someone',
              'lend_taken',
              Icons.payments_outlined,
            ),
            const SizedBox(height: 8),
            _buildLendOption(
              'Lend Returned',
              'Someone returned money to me',
              'lend_returned_income',
              Icons.check_circle_outline_rounded,
            ),
          ],
          if (_isLendFeatureEnabled && _selectedType == 'expense') ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Lend Options',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildLendOption(
              'Lend Given',
              'I lent money to someone',
              'lend_given',
              Icons.send_rounded,
            ),
            const SizedBox(height: 8),
            _buildLendOption(
              'Lend Returned',
              'I returned money to someone',
              'lend_returned_expense',
              Icons.assignment_return_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeButton(String label, String type, IconData icon, Color color) {
    final isSelected = _selectedType == type && _selectedLendType == null;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedType = type;
          _selectedLendType = null;
          _selectedCategory = null;
          _selectedPerson = null;
          _personNameController.clear();
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : AppColors.textSecondary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLendOption(String title, String subtitle, String type, IconData icon) {
    final isSelected = _selectedLendType == type;
    final color = _selectedType == 'income' ? AppColors.income : AppColors.expense;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedLendType = type;
          _selectedCategory = null;
          _selectedPerson = null;
          _personNameController.clear();
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? color.withOpacity(0.1) 
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: isSelected ? 2 : 0,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected 
                    ? color.withOpacity(0.2) 
                    : (isDark ? AppColors.darkSurfaceVariant : Colors.white),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? color : AppColors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected 
                          ? color 
                          : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonSelection(DataProvider dataProvider) {
    final isGivenOrTaken = _selectedLendType == 'lend_given' || _selectedLendType == 'lend_taken';
    final isReturning = _selectedLendType == 'lend_returned_income' || 
                       _selectedLendType == 'lend_returned_expense';
    
    List<String> existingPeople = [];
    if (isReturning) {
      existingPeople = _selectedLendType == 'lend_returned_income'
          ? dataProvider.getLendTakenPeople()
          : dataProvider.getLendGivenPeople();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGivenOrTaken
                  ? (_selectedLendType == 'lend_given' ? 'To Whom' : 'From Whom')
                  : 'Select Person',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (existingPeople.isNotEmpty && isReturning) ...[
              DropdownButtonFormField<String>(
                value: _selectedPerson,
                decoration: const InputDecoration(
                  hintText: 'Choose existing person',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: existingPeople.map((person) {
                  final outstanding = _selectedLendType == 'lend_returned_income'
                      ? dataProvider.getOutstandingLendTaken(person)
                      : dataProvider.getOutstandingLendGiven(person);
                  return DropdownMenuItem(
                    value: person,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            person,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          FormatUtils.formatCurrency(outstanding),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPerson = value;
                    _personNameController.text = value ?? '';
                  });
                },
                validator: (value) {
                  if (_personNameController.text.isEmpty) {
                    return 'Please select or enter a person';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _personNameController,
              decoration: InputDecoration(
                hintText: isGivenOrTaken ? 'Enter person name' : 'Enter new person',
                prefixIcon: const Icon(Icons.person_add_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter person name';
                }
                
                // For lend returns, check if person has outstanding amount
                if (_selectedLendType == 'lend_returned_income' || _selectedLendType == 'lend_returned_expense') {
                  final dataProvider = Provider.of<DataProvider>(context, listen: false);
                  final outstanding = _selectedLendType == 'lend_returned_income'
                      ? dataProvider.getOutstandingLendTaken(value.trim())
                      : dataProvider.getOutstandingLendGiven(value.trim());
                  
                  if (outstanding <= 0) {
                    return 'No outstanding amount for this person';
                  }
                }
                
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _selectedPerson = value.trim();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              prefixText: 'Rs ',
              prefixStyle: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
              hintText: '0.00',
              hintStyle: TextStyle(color: isDark ? AppColors.darkTextHint : AppColors.textHint),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter amount';
              }
              final amount = double.tryParse(value);
              if (amount == null) {
                return 'Please enter valid amount';
              }
              if (amount <= 0) {
                return 'Amount must be greater than 0';
              }
              
              // Check if user has sufficient balance for expense or lend_given
              if (_selectedAccount != null && 
                  (_selectedType == 'expense' || _selectedLendType == 'lend_given' || _selectedLendType == 'lend_returned_expense')) {
                if (amount > _selectedAccount!.balance) {
                  return 'Insufficient balance (Available: ${FormatUtils.formatCurrency(_selectedAccount!.balance)})';
                }
              }
              
              // Check if returning more than outstanding amount
              if ((_selectedLendType == 'lend_returned_income' || _selectedLendType == 'lend_returned_expense') && 
                  _personNameController.text.trim().isNotEmpty) {
                final dataProvider = Provider.of<DataProvider>(context, listen: false);
                final outstanding = _selectedLendType == 'lend_returned_income'
                    ? dataProvider.getOutstandingLendTaken(_personNameController.text.trim())
                    : dataProvider.getOutstandingLendGiven(_personNameController.text.trim());
                
                if (amount > outstanding) {
                  return 'Cannot return more than outstanding (${FormatUtils.formatCurrency(outstanding)})';
                }
              }
              
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(DataProvider dataProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Account>(
            value: _selectedAccount != null
                ? dataProvider.accounts.firstWhere(
                    (a) => a.id == _selectedAccount!.id,
                    orElse: () => _selectedAccount!,
                  )
                : null,
            decoration: InputDecoration(
              hintText: 'Select account',
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: isDark ? AppColors.darkBackground : AppColors.background,
            ),
            items: dataProvider.accounts.map((account) {
              return DropdownMenuItem(
                value: account,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        account.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      FormatUtils.formatCurrency(account.balance),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedAccount = value;
              });
            },
            validator: (value) {
              if (value == null) {
                return 'Please select account';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(DataProvider dataProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Category',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<app_models.Category>(
            value: _selectedCategory,
            decoration: InputDecoration(
              hintText: 'Select category',
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: const Icon(Icons.category_outlined, color: AppColors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: isDark ? AppColors.darkBackground : AppColors.background,
            ),
            items: (_selectedType == 'income'
                    ? dataProvider.incomeCategories
                    : dataProvider.expenseCategories)
                .map((category) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return DropdownMenuItem(
                value: category,
                child: Text(
                  category.name,
                  style: TextStyle(
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCategory = value;
              });
            },
            validator: (value) {
              if (value == null) {
                return 'Please select category';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Date',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
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
              if (date != null) {
                setState(() {
                  _selectedDate = date;
                });
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBackground : AppColors.background,
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      FormatUtils.formatDate(_selectedDate),
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemarksCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Remarks (Optional)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _remarksController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add notes about this transaction',
              hintStyle: const TextStyle(color: AppColors.textHint),
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: isDark ? AppColors.darkBackground : AppColors.background,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _saveTransaction,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 18),
        minimumSize: const Size(double.infinity, 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      child: const Text(
        'Save Transaction',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    final amount = double.parse(_amountController.text);
    final remarks = _remarksController.text.trim().isEmpty 
        ? null 
        : _remarksController.text.trim();

    String transactionType;
    int categoryId;
    String? personName;

    if (_isLendTransaction) {
      transactionType = _selectedLendType!;
      personName = _personNameController.text.trim();
      
      final categories = _selectedType == 'income' 
          ? dataProvider.incomeCategories 
          : dataProvider.expenseCategories;
      
      if (categories.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No categories available. Please add categories first.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      
      categoryId = categories.first.id!;
    } else {
      transactionType = _selectedType;
      categoryId = _selectedCategory!.id!;
      personName = null;
    }

    final transaction = model.Transaction(
      type: transactionType,
      amount: amount,
      accountId: _selectedAccount!.id!,
      categoryId: categoryId,
      date: _selectedDate,
      remarks: remarks,
      personName: personName,
    );

    try {
      await dataProvider.addTransaction(transaction);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction added successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

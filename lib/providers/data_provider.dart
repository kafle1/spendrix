import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../models/transaction.dart' as app_models;
import '../models/spending_limit.dart';

class DataProvider with ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  List<Account> _accounts = [];
  List<app_models.Category> _incomeCategories = [];
  List<app_models.Category> _expenseCategories = [];
  List<app_models.Transaction> _transactions = [];
  List<SpendingLimit> _spendingLimits = [];

  List<Account> get accounts => _accounts;
  List<app_models.Category> get incomeCategories => _incomeCategories;
  List<app_models.Category> get expenseCategories => _expenseCategories;
  List<app_models.Transaction> get transactions => _transactions;
  List<SpendingLimit> get spendingLimits => _spendingLimits;

  double get totalBalance {
    return _accounts.fold(0, (sum, account) => sum + account.balance);
  }

  Future<void> loadAllData() async {
    await loadAccounts();
    await loadCategories();
    await loadTransactions();
    await loadSpendingLimits();
  }

  Future<void> loadAccounts() async {
    _accounts = await _dbHelper.getAccounts();
    notifyListeners();
  }

  Future<void> addAccount(Account account) async {
    await _dbHelper.insertAccount(account);
    await loadAccounts();
  }

  Future<void> updateAccount(Account account) async {
    await _dbHelper.updateAccount(account);
    await loadAccounts();
  }

  Future<void> deleteAccount(int id) async {
    await _dbHelper.deleteAccount(id);
    await loadAccounts();
  }

  Future<void> loadCategories() async {
    _incomeCategories = await _dbHelper.getCategories(type: 'income');
    _expenseCategories = await _dbHelper.getCategories(type: 'expense');
    notifyListeners();
  }

  Future<void> addCategory(app_models.Category category) async {
    await _dbHelper.insertCategory(category);
    await loadCategories();
  }

  Future<void> updateCategory(app_models.Category category) async {
    await _dbHelper.updateCategory(category);
    await loadCategories();
  }

  Future<void> deleteCategory(int id) async {
    await _dbHelper.deleteCategory(id);
    await loadCategories();
  }

  Future<void> reorderCategories(List<app_models.Category> categories) async {
    for (int i = 0; i < categories.length; i++) {
      final category = categories[i];
      final updatedCategory = category.copyWith(displayOrder: i);
      await _dbHelper.updateCategory(updatedCategory);
    }
    await loadCategories();
  }

  Future<void> loadTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? type,
    int? accountId,
    int? categoryId,
  }) async {
    _transactions = await _dbHelper.getTransactions(
      startDate: startDate,
      endDate: endDate,
      type: type,
      accountId: accountId,
      categoryId: categoryId,
    );
    notifyListeners();
  }

  Future<void> addTransaction(app_models.Transaction transaction) async {
    await _dbHelper.insertTransaction(transaction);
    
    final accountIndex = _accounts.indexWhere((a) => a.id == transaction.accountId);
    if (accountIndex != -1) {
      final account = _accounts[accountIndex];
      double newBalance = account.balance;
      
      if (transaction.type == 'income' || 
          transaction.type == 'lend_taken' || 
          transaction.type == 'lend_returned_income') {
        newBalance = account.balance + transaction.amount;
      } else if (transaction.type == 'expense' || 
                 transaction.type == 'lend_given' || 
                 transaction.type == 'lend_returned_expense') {
        newBalance = account.balance - transaction.amount;
      }
      
      await updateAccount(account.copyWith(balance: newBalance));
    }
    
    await loadTransactions();
  }

  Future<void> updateTransaction(app_models.Transaction oldTransaction, app_models.Transaction newTransaction) async {
    if (oldTransaction.accountId == newTransaction.accountId) {
      final accountIndex = _accounts.indexWhere((a) => a.id == oldTransaction.accountId);
      if (accountIndex != -1) {
        final account = _accounts[accountIndex];
        double balanceAdjustment = 0;
        
        // Reverse old transaction
        if (oldTransaction.type == 'income' || 
            oldTransaction.type == 'lend_taken' || 
            oldTransaction.type == 'lend_returned_income') {
          balanceAdjustment -= oldTransaction.amount;
        } else if (oldTransaction.type == 'expense' || 
                   oldTransaction.type == 'lend_given' || 
                   oldTransaction.type == 'lend_returned_expense') {
          balanceAdjustment += oldTransaction.amount;
        }
        
        // Apply new transaction
        if (newTransaction.type == 'income' || 
            newTransaction.type == 'lend_taken' || 
            newTransaction.type == 'lend_returned_income') {
          balanceAdjustment += newTransaction.amount;
        } else if (newTransaction.type == 'expense' || 
                   newTransaction.type == 'lend_given' || 
                   newTransaction.type == 'lend_returned_expense') {
          balanceAdjustment -= newTransaction.amount;
        }
        
        await updateAccount(account.copyWith(balance: account.balance + balanceAdjustment));
      }
    } else {
      final oldAccountIndex = _accounts.indexWhere((a) => a.id == oldTransaction.accountId);
      final newAccountIndex = _accounts.indexWhere((a) => a.id == newTransaction.accountId);
      
      if (oldAccountIndex != -1) {
        final oldAccount = _accounts[oldAccountIndex];
        double oldBalance = oldAccount.balance;
        
        // Reverse old transaction
        if (oldTransaction.type == 'income' || 
            oldTransaction.type == 'lend_taken' || 
            oldTransaction.type == 'lend_returned_income') {
          oldBalance -= oldTransaction.amount;
        } else if (oldTransaction.type == 'expense' || 
                   oldTransaction.type == 'lend_given' || 
                   oldTransaction.type == 'lend_returned_expense') {
          oldBalance += oldTransaction.amount;
        }
        
        await updateAccount(oldAccount.copyWith(balance: oldBalance));
      }
      
      if (newAccountIndex != -1) {
        final newAccount = _accounts[newAccountIndex];
        double newBalance = newAccount.balance;
        
        // Apply new transaction
        if (newTransaction.type == 'income' || 
            newTransaction.type == 'lend_taken' || 
            newTransaction.type == 'lend_returned_income') {
          newBalance += newTransaction.amount;
        } else if (newTransaction.type == 'expense' || 
                   newTransaction.type == 'lend_given' || 
                   newTransaction.type == 'lend_returned_expense') {
          newBalance -= newTransaction.amount;
        }
        
        await updateAccount(newAccount.copyWith(balance: newBalance));
      }
    }
    
    await _dbHelper.updateTransaction(newTransaction);
    await loadTransactions();
  }

  Future<void> deleteTransaction(app_models.Transaction transaction) async {
    final accountIndex = _accounts.indexWhere((a) => a.id == transaction.accountId);
    if (accountIndex != -1) {
      final account = _accounts[accountIndex];
      double newBalance = account.balance;
      
      // Reverse the transaction
      if (transaction.type == 'income' || 
          transaction.type == 'lend_taken' || 
          transaction.type == 'lend_returned_income') {
        newBalance = account.balance - transaction.amount;
      } else if (transaction.type == 'expense' || 
                 transaction.type == 'lend_given' || 
                 transaction.type == 'lend_returned_expense') {
        newBalance = account.balance + transaction.amount;
      }
      
      await updateAccount(account.copyWith(balance: newBalance));
    }
    
    await _dbHelper.deleteTransaction(transaction.id!);
    await loadTransactions();
  }



  Future<void> loadSpendingLimits() async {
    _spendingLimits = await _dbHelper.getSpendingLimits();
    notifyListeners();
  }

  Future<void> addSpendingLimit(SpendingLimit limit) async {
    await _dbHelper.insertSpendingLimit(limit);
    await loadSpendingLimits();
  }

  Future<void> updateSpendingLimit(SpendingLimit limit) async {
    await _dbHelper.updateSpendingLimit(limit);
    await loadSpendingLimits();
  }

  Future<void> deleteSpendingLimit(int id) async {
    await _dbHelper.deleteSpendingLimit(id);
    await loadSpendingLimits();
  }

  double getTotalIncome({DateTime? startDate, DateTime? endDate}) {
    return _transactions
        .where((t) =>
            (t.type == 'income' || t.type == 'lend_taken' || t.type == 'lend_returned_income') &&
            (startDate == null || !t.date.isBefore(startDate)) &&
            (endDate == null || !t.date.isAfter(endDate)))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double getTotalExpense({DateTime? startDate, DateTime? endDate}) {
    return _transactions
        .where((t) =>
            (t.type == 'expense' || t.type == 'lend_given' || t.type == 'lend_returned_expense') &&
            (startDate == null || !t.date.isBefore(startDate)) &&
            (endDate == null || !t.date.isAfter(endDate)))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  Map<int, double> getExpensesByCategory({DateTime? startDate, DateTime? endDate}) {
    final categoryExpenses = <int, double>{};
    
    final filteredTransactions = _transactions.where((t) =>
        t.type == 'expense' &&
        (startDate == null || !t.date.isBefore(startDate)) &&
        (endDate == null || !t.date.isAfter(endDate)));

    for (var transaction in filteredTransactions) {
      categoryExpenses[transaction.categoryId] =
          (categoryExpenses[transaction.categoryId] ?? 0.0) + transaction.amount;
    }

    return categoryExpenses;
  }

  double getCategoryExpenses({
    required int categoryId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _transactions
        .where((t) =>
            t.type == 'expense' &&
            t.categoryId == categoryId &&
            (startDate == null || !t.date.isBefore(startDate)) &&
            (endDate == null || !t.date.isAfter(endDate)))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  double getSpendingForLimit(SpendingLimit limit) {
    final now = DateTime.now();
    DateTime startDate;
    DateTime endDate;

    switch (limit.period) {
      case 'daily':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'weekly':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        endDate = startDate.add(const Duration(days: 7));
        break;
      case 'monthly':
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'custom':
        startDate = limit.startDate;
        endDate = limit.endDate ?? now;
        break;
      default:
        startDate = limit.startDate;
        endDate = now;
    }

    return _transactions
        .where((t) =>
            t.type == 'expense' &&
            !t.date.isBefore(startDate) &&
            !t.date.isAfter(endDate) &&
            (limit.accountIds.isEmpty || limit.accountIds.contains(t.accountId)) &&
            (limit.categoryIds.isEmpty || limit.categoryIds.contains(t.categoryId)))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  // Get unique people from lend transactions
  List<String> getLendGivenPeople() {
    return _transactions
        .where((t) => t.type == 'lend_given' && t.personName != null)
        .map((t) => t.personName!)
        .toSet()
        .toList()..sort();
  }

  List<String> getLendTakenPeople() {
    return _transactions
        .where((t) => t.type == 'lend_taken' && t.personName != null)
        .map((t) => t.personName!)
        .toSet()
        .toList()..sort();
  }

  // Calculate outstanding lend amount for a person
  double getOutstandingLendGiven(String personName) {
    final given = _transactions
        .where((t) => t.type == 'lend_given' && t.personName == personName)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final returned = _transactions
        .where((t) => t.type == 'lend_returned_expense' && t.personName == personName)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    return given - returned;
  }

  double getOutstandingLendTaken(String personName) {
    final taken = _transactions
        .where((t) => t.type == 'lend_taken' && t.personName == personName)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final returned = _transactions
        .where((t) => t.type == 'lend_returned_income' && t.personName == personName)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    return taken - returned;
  }

  // Get total lend statistics
  double getTotalLendGiven() {
    return getLendGivenPeople()
        .fold(0.0, (sum, person) => sum + getOutstandingLendGiven(person));
  }

  double getTotalLendTaken() {
    return getLendTakenPeople()
        .fold(0.0, (sum, person) => sum + getOutstandingLendTaken(person));
  }

  // Reset all data
  Future<void> resetAllData() async {
    await _dbHelper.resetAllData();
    _accounts = [];
    _incomeCategories = [];
    _expenseCategories = [];
    _transactions = [];
    _spendingLimits = [];
    notifyListeners();
  }
}

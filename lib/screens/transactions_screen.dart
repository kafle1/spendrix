import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/data_provider.dart';
import '../models/transaction.dart' as model;
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../utils/app_theme.dart';
import '../utils/format_utils.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  String _selectedPeriod = 'all';
  String? _selectedType;
  int? _selectedAccountId;
  int? _selectedCategoryId;
  bool _showLending = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showLending = prefs.getBool('isDashboardLendingEnabled') ?? true;
      });
    }
  }

  List<model.Transaction> _getFilteredTransactions(DataProvider dataProvider) {
    var transactions = dataProvider.transactions;

    // Filter by lending visibility
    if (!_showLending) {
      transactions = transactions.where((t) =>
        t.type != 'lend_taken' &&
        t.type != 'lend_given' &&
        t.type != 'lend_returned_income' &&
        t.type != 'lend_returned_expense'
      ).toList();
    }

    // Filter by type
    if (_selectedType != null) {
      transactions = transactions.where((t) => t.type == _selectedType).toList();
    }

    // Filter by account
    if (_selectedAccountId != null) {
      transactions = transactions.where((t) => t.accountId == _selectedAccountId).toList();
    }

    // Filter by category
    if (_selectedCategoryId != null) {
      transactions = transactions.where((t) => t.categoryId == _selectedCategoryId).toList();
    }

    // Filter by period
    final now = DateTime.now();
    if (_selectedPeriod != 'all') {
      transactions = transactions.where((t) {
        switch (_selectedPeriod) {
          case 'daily':
            return t.date.year == now.year && t.date.month == now.month && t.date.day == now.day;
          case 'weekly':
            final weekStart = now.subtract(Duration(days: now.weekday - 1));
            final weekEnd = weekStart.add(const Duration(days: 6));
            return t.date.isAfter(weekStart.subtract(const Duration(days: 1))) && 
                   t.date.isBefore(weekEnd.add(const Duration(days: 1)));
          case 'monthly':
            return t.date.year == now.year && t.date.month == now.month;
          case 'yearly':
            return t.date.year == now.year;
          default:
            return true;
        }
      }).toList();
    }

    return transactions;
  }

  Future<void> _exportToPDF(List<model.Transaction> transactions, DataProvider dataProvider) async {
    final pdf = pw.Document();
    
    // Calculate totals
    double totalIncome = 0;
    double totalExpense = 0;
    for (var t in transactions) {
      final isIncome = t.type == 'income' || t.type == 'lend_taken' || t.type == 'lend_returned_income';
      if (isIncome) {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Spendrix',
                  style: pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Transaction Report',
                  style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
              ],
            ),
          ),

          // Summary
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Total Income', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        FormatUtils.formatCurrency(totalIncome),
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.red50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Total Expense', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        FormatUtils.formatCurrency(totalExpense),
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 24),
          pw.Text(
            'Transactions (${transactions.length})',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),

          // Transactions Table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Type', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(8),
                    child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
              // Data rows
              ...transactions.map((transaction) {
                final isIncome = transaction.type == 'income' || 
                                 transaction.type == 'lend_taken' || 
                                 transaction.type == 'lend_returned_income';

                String displayName;
                if (transaction.type == 'lend_taken') {
                  displayName = 'Lend Taken${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                } else if (transaction.type == 'lend_given') {
                  displayName = 'Lend Given${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                } else if (transaction.type == 'lend_returned_income' || transaction.type == 'lend_returned_expense') {
                  displayName = 'Lend Returned${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                } else {
                  final categories = isIncome ? dataProvider.incomeCategories : dataProvider.expenseCategories;
                  final category = categories.firstWhere(
                    (c) => c.id == transaction.categoryId,
                    orElse: () => app_models.Category(name: 'Unknown', type: transaction.type),
                  );
                  displayName = category.name;
                }

                return pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(FormatUtils.formatDate(transaction.date), style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(isIncome ? 'Income' : 'Expense', style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(displayName, style: const pw.TextStyle(fontSize: 10)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        FormatUtils.formatCurrency(transaction.amount),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: isIncome ? PdfColors.green900 : PdfColors.red900,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),

          // Footer
          pw.SizedBox(height: 24),
          pw.Divider(),
          pw.SizedBox(height: 8),
          pw.Text(
            'Generated on ${FormatUtils.formatDate(DateTime.now())} | Spendrix',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Transactions'),
        elevation: 0,
        actions: [
          Consumer<DataProvider>(
            builder: (context, dataProvider, child) {
              final transactions = _getFilteredTransactions(dataProvider);
              return IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: transactions.isEmpty
                    ? null
                    : () => _exportToPDF(transactions, dataProvider),
                tooltip: 'Export to PDF',
              );
            },
          ),
        ],
      ),
      body: Consumer<DataProvider>(
        builder: (context, dataProvider, child) {
          final transactions = _getFilteredTransactions(dataProvider);
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return Column(
            children: [
              // Filters
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filter Transactions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        setState(() {
                          _selectedPeriod = value;
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'all',
                          child: Row(
                            children: [
                              Icon(Icons.all_inclusive_rounded, size: 20),
                              SizedBox(width: 12),
                              Text('All Time'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'daily',
                          child: Row(
                            children: [
                              Icon(Icons.today_rounded, size: 20),
                              SizedBox(width: 12),
                              Text('Today'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'weekly',
                          child: Row(
                            children: [
                              Icon(Icons.view_week_rounded, size: 20),
                              SizedBox(width: 12),
                              Text('This Week'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'monthly',
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 20),
                              SizedBox(width: 12),
                              Text('This Month'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'yearly',
                          child: Row(
                            children: [
                              Icon(Icons.date_range_rounded, size: 20),
                              SizedBox(width: 12),
                              Text('This Year'),
                            ],
                          ),
                        ),
                      ],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedPeriod == 'all' ? 'All Time' :
                              _selectedPeriod == 'daily' ? 'Today' :
                              _selectedPeriod == 'weekly' ? 'This Week' :
                              _selectedPeriod == 'monthly' ? 'This Month' : 'This Year',
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
                  ],
                ),
              ),

              // Transactions List
              Expanded(
                child: transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No transactions found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your filters',
                              style: TextStyle(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = transactions[index];
                          final account = dataProvider.accounts.firstWhere(
                            (a) => a.id == transaction.accountId,
                            orElse: () => Account(name: 'Unknown', balance: 0, type: 'other'),
                          );

                          final isIncome = transaction.type == 'income' ||
                              transaction.type == 'lend_taken' ||
                              transaction.type == 'lend_returned_income';

                          String displayName;
                          if (transaction.type == 'lend_taken') {
                            displayName = 'Lend Taken${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                          } else if (transaction.type == 'lend_given') {
                            displayName = 'Lend Given${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                          } else if (transaction.type == 'lend_returned_income' || transaction.type == 'lend_returned_expense') {
                            displayName = 'Lend Returned${transaction.personName != null ? " - ${transaction.personName}" : ""}';
                          } else {
                            final categories = isIncome ? dataProvider.incomeCategories : dataProvider.expenseCategories;
                            final category = categories.firstWhere(
                              (c) => c.id == transaction.categoryId,
                              orElse: () => app_models.Category(name: 'Unknown', type: transaction.type),
                            );
                            displayName = category.name;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurface : AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark ? AppColors.darkBorder : AppColors.border,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isIncome
                                      ? AppColors.income.withValues(alpha: 0.1)
                                      : AppColors.expense.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  color: isIncome ? AppColors.income : AppColors.expense,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                displayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${account.name} • ${FormatUtils.formatDate(transaction.date)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              trailing: Text(
                                '${isIncome ? '+' : '-'} ${FormatUtils.formatCurrency(transaction.amount)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isIncome ? AppColors.income : AppColors.expense,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

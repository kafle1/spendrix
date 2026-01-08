import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/data_provider.dart';

/// Service for exporting all Spendrix app data to JSON format.
/// 
/// This service provides functionality to export user data for backup
/// and data portability purposes.
/// 
/// ## JSON Export Schema (v1)
/// 
/// ```json
/// {
///   "metadata": {
///     "appName": "Spendrix",
///     "version": "1.3.0",
///     "exportedAt": "2025-12-09T10:00:00.000Z",
///     "schemaVersion": 1
///   },
///   "data": {
///     "accounts": [{ "id": 1, "name": "Cash", "balance": 5000.0, ... }],
///     "categories": {
///       "income": [{ "id": 1, "name": "Salary", "type": "income", ... }],
///       "expense": [{ "id": 2, "name": "Food", "type": "expense", ... }]
///     },
///     "transactions": [{ "id": 1, "type": "expense", "amount": 100.0, ... }],
///     "spendingLimits": [{ "id": 1, "name": "Monthly Food", ... }],
///     "lendRecords": [{ "id": 1, "type": "given", "personName": "John", ... }]
///   },
///   "summary": {
///     "totalAccounts": 3,
///     "totalCategories": 15,
///     "totalTransactions": 150,
///     "totalSpendingLimits": 2,
///     "totalLendRecords": 5
///   }
/// }
/// ```
/// 
/// The `schemaVersion` field enables future import functionality to handle
/// backward compatibility when the data structure changes.
class DataExportService {
  /// Current schema version for the export format.
  /// Increment this when making breaking changes to the export structure.
  static const int schemaVersion = 1;
  
  /// App name for metadata
  static const String appName = 'Spendrix';
  
  /// App version
  static const String appVersion = '1.3.0';
  
  /// Generates a timestamped filename for exports.
  /// Format: spendrix_backup_YYYYMMDD_HHMMSS.json
  static String generateFileName() {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'spendrix_backup_$timestamp.json';
  }
  
  /// Checks if the data provider has any data to export.
  /// Returns true if at least one data collection is non-empty.
  static bool hasData(DataProvider dataProvider) {
    return dataProvider.accounts.isNotEmpty ||
           dataProvider.incomeCategories.isNotEmpty ||
           dataProvider.expenseCategories.isNotEmpty ||
           dataProvider.transactions.isNotEmpty ||
           dataProvider.spendingLimits.isNotEmpty ||
           dataProvider.lendRecords.isNotEmpty;
  }
  
  /// Exports all app data to a JSON string.
  /// 
  /// Returns a pretty-printed JSON string containing all user data
  /// with metadata and summary information.
  static Future<String> exportToJson(DataProvider dataProvider) async {
    // Collect all data from the provider
    final accounts = dataProvider.accounts.map((a) => a.toMap()).toList();
    final incomeCategories = dataProvider.incomeCategories.map((c) => c.toMap()).toList();
    final expenseCategories = dataProvider.expenseCategories.map((c) => c.toMap()).toList();
    final transactions = dataProvider.transactions.map((t) => t.toMap()).toList();
    final spendingLimits = dataProvider.spendingLimits.map((s) => s.toMap()).toList();
    final lendRecords = dataProvider.lendRecords.map((l) => l.toMap()).toList();
    
    // Build the export data structure
    final exportData = {
      'metadata': {
        'appName': appName,
        'version': appVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'schemaVersion': schemaVersion,
      },
      'data': {
        'accounts': accounts,
        'categories': {
          'income': incomeCategories,
          'expense': expenseCategories,
        },
        'transactions': transactions,
        'spendingLimits': spendingLimits,
        'lendRecords': lendRecords,
      },
      'summary': {
        'totalAccounts': accounts.length,
        'totalCategories': incomeCategories.length + expenseCategories.length,
        'totalTransactions': transactions.length,
        'totalSpendingLimits': spendingLimits.length,
        'totalLendRecords': lendRecords.length,
      },
    };
    
    // Convert to pretty-printed JSON
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(exportData);
  }
  
  /// Exports data and shares the file using the native share dialog.
  /// 
  /// Creates a temporary file with the exported JSON data, opens the
  /// native share dialog, and cleans up the temp file after sharing.
  /// 
  /// Returns the [ShareResult] indicating the outcome of the share operation.
  static Future<ShareResult> exportAndShare(DataProvider dataProvider) async {
    // Generate JSON data
    final jsonData = await exportToJson(dataProvider);
    
    // Save to a temporary file for sharing
    final directory = await getTemporaryDirectory();
    final fileName = generateFileName();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonData);
    
    ShareResult result;
    try {
      // Share the file
      result = await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Spendrix Data Export',
        text: 'My Spendrix expense tracker data backup',
      );
    } finally {
      // Explicitly clean up the temporary file
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          // Log cleanup errors in debug mode, but don't fail the operation
          debugPrint('Failed to clean up temp export file: $e');
        }
      }
    }
    
    return result;
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/data_provider.dart';

/// Service for exporting all app data to JSON format
class DataExportService {
  /// Current schema version for the export format
  static const int schemaVersion = 1;
  
  /// App name for metadata
  static const String appName = 'Spendrix';
  
  /// Generates a timestamped filename for exports
  static String generateFileName() {
    final now = DateTime.now();
    final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'spendrix_backup_$timestamp.json';
  }
  
  /// Exports all app data to a JSON string
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
        'version': '1.3.0', // App version from pubspec
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
  
  /// Saves JSON data to a file and returns the file path
  static Future<File> saveToFile(String jsonData) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = generateFileName();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonData);
    return file;
  }
  
  /// Exports data and shares the file using the native share dialog
  static Future<ShareResult> exportAndShare(DataProvider dataProvider) async {
    // Generate JSON data
    final jsonData = await exportToJson(dataProvider);
    
    // Save to a temporary file for sharing
    final directory = await getTemporaryDirectory();
    final fileName = generateFileName();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonData);
    
    // Share the file
    final result = await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Spendrix Data Export',
      text: 'My Spendrix expense tracker data backup',
    );
    
    return result;
  }
  
  /// Saves data to downloads folder and returns the file
  static Future<File> exportToDownloads(DataProvider dataProvider) async {
    final jsonData = await exportToJson(dataProvider);
    
    // Try to get downloads directory, fallback to documents
    Directory? directory;
    try {
      directory = await getDownloadsDirectory();
    } catch (_) {
      // Downloads directory might not be available on all platforms
    }
    directory ??= await getApplicationDocumentsDirectory();
    
    final fileName = generateFileName();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(jsonData);
    
    return file;
  }
}

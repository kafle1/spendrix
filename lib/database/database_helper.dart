import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/category.dart' as app_models;
import '../models/transaction.dart' as app_models;
import '../models/spending_limit.dart';
import '../models/lend_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expense_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        balance REAL NOT NULL,
        type TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        iconName TEXT,
        colorHex TEXT,
        displayOrder INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        accountId INTEGER NOT NULL,
        categoryId INTEGER NOT NULL,
        date TEXT NOT NULL,
        remarks TEXT,
        personName TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (accountId) REFERENCES accounts (id),
        FOREIGN KEY (categoryId) REFERENCES categories (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE spending_limits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        limitAmount REAL NOT NULL,
        period TEXT NOT NULL,
        accountIds TEXT NOT NULL,
        categoryIds TEXT NOT NULL,
        startDate TEXT NOT NULL,
        endDate TEXT,
        isActive INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE lend_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        personName TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        remarks TEXT,
        isSettled INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE transactions ADD COLUMN personName TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS lend_borrow');
      try {
        await db.execute('ALTER TABLE accounts DROP COLUMN lentAmount');
      } catch (e) {
        // SQLite doesn't support DROP COLUMN, recreate table
        await db.execute('''
          CREATE TABLE accounts_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            balance REAL NOT NULL,
            type TEXT NOT NULL,
            createdAt TEXT NOT NULL
          )
        ''');
        await db.execute('''
          INSERT INTO accounts_new (id, name, balance, type, createdAt)
          SELECT id, name, balance, type, createdAt FROM accounts
        ''');
        await db.execute('DROP TABLE accounts');
        await db.execute('ALTER TABLE accounts_new RENAME TO accounts');
      }
    }
    if (oldVersion < 4) {
      // Add displayOrder column to categories table
      try {
        await db.execute('ALTER TABLE categories ADD COLUMN displayOrder INTEGER');
      } catch (e) {
        // If column already exists, ignore
      }
    }
    if (oldVersion < 5) {
      // Add lend_records table
      await db.execute('''
        CREATE TABLE lend_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          personName TEXT NOT NULL,
          amount REAL NOT NULL,
          date TEXT NOT NULL,
          remarks TEXT,
          isSettled INTEGER NOT NULL DEFAULT 0,
          createdAt TEXT NOT NULL
        )
      ''');
    }
  }

  Future<int> insertAccount(Account account) async {
    final db = await database;
    return await db.insert('accounts', account.toMap());
  }

  Future<List<Account>> getAccounts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');
    return List.generate(maps.length, (i) => Account.fromMap(maps[i]));
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;
    return await db.update(
      'accounts',
      account.toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertCategory(app_models.Category category) async {
    final db = await database;
    return await db.insert('categories', category.toMap());
  }

  Future<List<app_models.Category>> getCategories({String? type}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = type != null
        ? await db.query('categories', where: 'type = ?', whereArgs: [type], orderBy: 'displayOrder ASC, id ASC')
        : await db.query('categories', orderBy: 'displayOrder ASC, id ASC');
    return List.generate(maps.length, (i) => app_models.Category.fromMap(maps[i]));
  }

  Future<int> updateCategory(app_models.Category category) async {
    final db = await database;
    return await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertTransaction(app_models.Transaction transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction.toMap());
  }

  Future<List<app_models.Transaction>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? type,
    int? accountId,
    int? categoryId,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClause += 'date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    if (type != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'type = ?';
      whereArgs.add(type);
    }

    if (accountId != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'accountId = ?';
      whereArgs.add(accountId);
    }

    if (categoryId != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'categoryId = ?';
      whereArgs.add(categoryId);
    }

    final List<Map<String, dynamic>> maps = whereClause.isNotEmpty
        ? await db.query(
            'transactions',
            where: whereClause,
            whereArgs: whereArgs,
            orderBy: 'date DESC',
          )
        : await db.query('transactions', orderBy: 'date DESC');

    return List.generate(maps.length, (i) => app_models.Transaction.fromMap(maps[i]));
  }

  Future<int> updateTransaction(app_models.Transaction transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSpendingLimit(SpendingLimit limit) async {
    final db = await database;
    return await db.insert('spending_limits', limit.toMap());
  }

  Future<List<SpendingLimit>> getSpendingLimits({bool? isActive}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = isActive != null
        ? await db.query(
            'spending_limits',
            where: 'isActive = ?',
            whereArgs: [isActive ? 1 : 0],
          )
        : await db.query('spending_limits');

    return List.generate(maps.length, (i) => SpendingLimit.fromMap(maps[i]));
  }

  Future<int> updateSpendingLimit(SpendingLimit limit) async {
    final db = await database;
    return await db.update(
      'spending_limits',
      limit.toMap(),
      where: 'id = ?',
      whereArgs: [limit.id],
    );
  }

  Future<int> deleteSpendingLimit(int id) async {
    final db = await database;
    return await db.delete('spending_limits', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertLendRecord(LendRecord record) async {
    final db = await database;
    return await db.insert('lend_records', record.toMap());
  }

  Future<List<LendRecord>> getLendRecords({
    String? type,
    String? personName,
    bool? isSettled,
  }) async {
    final db = await database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (type != null) {
      whereClause += 'type = ?';
      whereArgs.add(type);
    }

    if (personName != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'personName = ?';
      whereArgs.add(personName);
    }

    if (isSettled != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'isSettled = ?';
      whereArgs.add(isSettled ? 1 : 0);
    }

    final List<Map<String, dynamic>> maps = whereClause.isNotEmpty
        ? await db.query(
            'lend_records',
            where: whereClause,
            whereArgs: whereArgs,
            orderBy: 'date DESC',
          )
        : await db.query('lend_records', orderBy: 'date DESC');

    return List.generate(maps.length, (i) => LendRecord.fromMap(maps[i]));
  }

  Future<int> updateLendRecord(LendRecord record) async {
    final db = await database;
    return await db.update(
      'lend_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteLendRecord(int id) async {
    final db = await database;
    return await db.delete('lend_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetAllData() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('spending_limits');
    await db.delete('categories');
    await db.delete('accounts');
    await db.delete('lend_records');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

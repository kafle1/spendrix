class Transaction {
  final int? id;
  final String type;
  final double amount;
  final int accountId;
  final int categoryId;
  final DateTime date;
  final String? remarks;
  final String? personName;
  final DateTime createdAt;

  Transaction({
    this.id,
    required this.type,
    required this.amount,
    required this.accountId,
    required this.categoryId,
    required this.date,
    this.remarks,
    this.personName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'accountId': accountId,
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'remarks': remarks,
      'personName': personName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      type: map['type'] as String,
      amount: map['amount'] as double,
      accountId: map['accountId'] as int,
      categoryId: map['categoryId'] as int,
      date: DateTime.parse(map['date'] as String),
      remarks: map['remarks'] as String?,
      personName: map['personName'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Transaction copyWith({
    int? id,
    String? type,
    double? amount,
    int? accountId,
    int? categoryId,
    DateTime? date,
    String? remarks,
    String? personName,
    DateTime? createdAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      remarks: remarks ?? this.remarks,
      personName: personName ?? this.personName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

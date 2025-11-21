class LendRecord {
  final int? id;
  final String type; // 'given' or 'taken'
  final String personName;
  final double amount;
  final DateTime date;
  final String? remarks;
  final bool isSettled;
  final DateTime createdAt;

  LendRecord({
    this.id,
    required this.type,
    required this.personName,
    required this.amount,
    required this.date,
    this.remarks,
    this.isSettled = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'personName': personName,
      'amount': amount,
      'date': date.toIso8601String(),
      'remarks': remarks,
      'isSettled': isSettled ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory LendRecord.fromMap(Map<String, dynamic> map) {
    return LendRecord(
      id: map['id'] as int?,
      type: map['type'] as String,
      personName: map['personName'] as String,
      amount: map['amount'] as double,
      date: DateTime.parse(map['date'] as String),
      remarks: map['remarks'] as String?,
      isSettled: map['isSettled'] == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  LendRecord copyWith({
    int? id,
    String? type,
    String? personName,
    double? amount,
    DateTime? date,
    String? remarks,
    bool? isSettled,
    DateTime? createdAt,
  }) {
    return LendRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      remarks: remarks ?? this.remarks,
      isSettled: isSettled ?? this.isSettled,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

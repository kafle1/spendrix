class Account {
  final int? id;
  final String name;
  final double balance;
  final String type;
  final DateTime createdAt;

  Account({
    this.id,
    required this.name,
    required this.balance,
    required this.type,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'balance': balance,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String,
      balance: map['balance'] as double,
      type: map['type'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Account copyWith({
    int? id,
    String? name,
    double? balance,
    String? type,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

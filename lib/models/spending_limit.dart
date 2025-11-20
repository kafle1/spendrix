class SpendingLimit {
  final int? id;
  final String name;
  final double limitAmount;
  final String period;
  final List<int> accountIds;
  final List<int> categoryIds;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;

  SpendingLimit({
    this.id,
    required this.name,
    required this.limitAmount,
    required this.period,
    required this.accountIds,
    required this.categoryIds,
    required this.startDate,
    this.endDate,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'limitAmount': limitAmount,
      'period': period,
      'accountIds': accountIds.join(','),
      'categoryIds': categoryIds.join(','),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'isActive': isActive ? 1 : 0,
    };
  }

  factory SpendingLimit.fromMap(Map<String, dynamic> map) {
    return SpendingLimit(
      id: map['id'] as int?,
      name: map['name'] as String,
      limitAmount: map['limitAmount'] as double,
      period: map['period'] as String,
      accountIds: (map['accountIds'] as String)
          .split(',')
          .where((s) => s.isNotEmpty)
          .map((s) => int.parse(s))
          .toList(),
      categoryIds: (map['categoryIds'] as String)
          .split(',')
          .where((s) => s.isNotEmpty)
          .map((s) => int.parse(s))
          .toList(),
      startDate: DateTime.parse(map['startDate'] as String),
      endDate: map['endDate'] != null
          ? DateTime.parse(map['endDate'] as String)
          : null,
      isActive: map['isActive'] == 1,
    );
  }

  SpendingLimit copyWith({
    int? id,
    String? name,
    double? limitAmount,
    String? period,
    List<int>? accountIds,
    List<int>? categoryIds,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
  }) {
    return SpendingLimit(
      id: id ?? this.id,
      name: name ?? this.name,
      limitAmount: limitAmount ?? this.limitAmount,
      period: period ?? this.period,
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
    );
  }
}

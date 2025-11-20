class Category {
  final int? id;
  final String name;
  final String type;
  final String? iconName;
  final String? colorHex;

  Category({
    this.id,
    required this.name,
    required this.type,
    this.iconName,
    this.colorHex,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'iconName': iconName,
      'colorHex': colorHex,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      iconName: map['iconName'] as String?,
      colorHex: map['colorHex'] as String?,
    );
  }

  Category copyWith({
    int? id,
    String? name,
    String? type,
    String? iconName,
    String? colorHex,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      iconName: iconName ?? this.iconName,
      colorHex: colorHex ?? this.colorHex,
    );
  }
}

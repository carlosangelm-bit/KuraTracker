class Site {
  final String id;
  final String name;
  final String kind; // clinica | domicilio | hospital | otro
  final String? address;
  final bool isActive;

  const Site({
    required this.id,
    required this.name,
    required this.kind,
    this.address,
    this.isActive = true,
  });

  factory Site.fromJson(Map<String, dynamic> json) => Site(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String? ?? 'clinica',
        address: json['address'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'address': address,
        'is_active': isActive,
      };
}

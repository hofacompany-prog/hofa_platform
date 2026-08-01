class Merchant {
  final String id;
  final String name;
  final String? logoUrl;
  final String? phone;

  Merchant({required this.id, required this.name, this.logoUrl, this.phone});

  factory Merchant.fromJson(Map<String, dynamic> json) => Merchant(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        phone: json['phone'] as String?,
      );
}

class UserProfile {
  final String id;
  final String phone;
  final String? email;
  final String fullName;
  final String role;
  final String status;

  UserProfile({
    required this.id,
    required this.phone,
    this.email,
    required this.fullName,
    required this.role,
    required this.status,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String?,
        fullName: json['full_name'] as String? ?? '',
        role: json['role'] as String? ?? 'customer',
        status: json['status'] as String? ?? 'active',
      );

  bool get isMerchant => role == 'merchant_owner' || role == 'merchant_staff';
}

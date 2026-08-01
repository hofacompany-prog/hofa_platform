class UserProfile {
  final String id;
  final String phone;
  final String? email;
  final String fullName;
  final String role;
  final String status;
  final String? avatarUrl;
  final DateTime? dateOfBirth;
  final DateTime? phoneVerifiedAt;
  final DateTime? emailVerifiedAt;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  UserProfile({
    required this.id,
    required this.phone,
    this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.avatarUrl,
    this.dateOfBirth,
    this.phoneVerifiedAt,
    this.emailVerifiedAt,
    this.lastLoginAt,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String?,
        fullName: json['full_name'] as String? ?? '',
        role: json['role'] as String? ?? 'customer',
        status: json['status'] as String? ?? 'active',
        avatarUrl: json['avatar_url'] as String?,
        dateOfBirth: json['date_of_birth'] != null ? DateTime.tryParse(json['date_of_birth'] as String) : null,
        phoneVerifiedAt:
            json['phone_verified_at'] != null ? DateTime.tryParse(json['phone_verified_at'] as String) : null,
        emailVerifiedAt:
            json['email_verified_at'] != null ? DateTime.tryParse(json['email_verified_at'] as String) : null,
        lastLoginAt: json['last_login_at'] != null ? DateTime.tryParse(json['last_login_at'] as String) : null,
        createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
        updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
        deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
      );

  bool get isMerchant => role == 'merchant_owner' || role == 'merchant_staff';
}

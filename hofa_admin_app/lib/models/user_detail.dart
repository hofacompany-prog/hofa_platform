import 'address.dart';
import 'user_profile.dart';

class UserDetail {
  final UserProfile profile;
  final List<Address> addresses;

  UserDetail({required this.profile, required this.addresses});

  factory UserDetail.fromJson(Map<String, dynamic> json) => UserDetail(
        profile: UserProfile.fromJson(json),
        addresses: (json['addresses'] as List? ?? [])
            .map((e) => Address.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

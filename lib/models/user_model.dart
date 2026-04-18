import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phoneNumber;
  final String? profilePicture;
  final String? dob;      // stored as 'YYYY-MM-DD'; empty string means cleared
  final String? gender;   // 'Male' | 'Female' | 'Non-binary' | 'Prefer not to say'
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.phoneNumber,
    this.profilePicture,
    this.dob,
    this.gender,
    required this.createdAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] as String?,
      profilePicture: data['profilePicture'] as String?,
      dob: data['dob'] as String?,
      gender: data['gender'] as String?,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber,
      'profilePicture': profilePicture,
      'dob': dob,
      'gender': gender,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// Pass a non-null value to update that field; null means keep existing.
  /// Pass an empty string ('') to explicitly clear an optional field.
  UserModel copyWith({
    String? name,
    String? phoneNumber,
    String? profilePicture,
    String? dob,
    String? gender,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profilePicture: profilePicture ?? this.profilePicture,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      createdAt: createdAt,
    );
  }

  bool get hasProfilePicture =>
      profilePicture != null && profilePicture!.isNotEmpty;

  @override
  String toString() => 'UserModel(uid: $uid, name: $name, email: $email)';
}

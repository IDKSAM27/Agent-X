class UserProfile {
  final String uid;
  final String name;
  final String profession; // e.g., Student, Teacher, Developer, etc.

  UserProfile({
    required this.uid,
    required this.name,
    required this.profession,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'profession': profession,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'],
      name: map['name'],
      profession: map['profession'],
    );
  }
}

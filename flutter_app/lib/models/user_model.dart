class UserModel {
  final String id;
  final String name;
  final String email;
  final String institution;
  final String researchField;
  final DateTime joinedDate;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.institution,
    required this.researchField,
    required this.joinedDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'institution': institution,
      'researchField': researchField,
      'joinedDate': joinedDate.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<dynamic, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      institution: map['institution'] ?? '',
      researchField: map['researchField'] ?? '',
      joinedDate: map['joinedDate'] != null
          ? DateTime.parse(map['joinedDate'])
          : DateTime.now(),
    );
  }
}

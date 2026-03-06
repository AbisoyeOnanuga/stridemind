class StravaAthlete {
  final int id;
  final String? username;
  final String firstname;
  final String lastname;
  final String? profileMedium; // URL to medium profile picture
  final String? profile;       // URL to large profile picture

  StravaAthlete({
    required this.id,
    this.username,
    required this.firstname,
    required this.lastname,
    this.profileMedium,
    this.profile,
  });

  factory StravaAthlete.fromJson(Map<String, dynamic> json) {
    return StravaAthlete(
      id: json['id'],
      username: json['username'],
      firstname: json['firstname'] ?? '',
      lastname: json['lastname'] ?? '',
      profileMedium: json['profile_medium'],
      profile: json['profile'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (username != null) 'username': username,
        'firstname': firstname,
        'lastname': lastname,
        if (profileMedium != null) 'profile_medium': profileMedium,
        if (profile != null) 'profile': profile,
      };
}
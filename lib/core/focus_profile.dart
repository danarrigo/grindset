class FocusProfile {
  FocusProfile({
    required this.id,
    required String name,
    required Iterable<String> ruleIds,
  }) : name = name.trim(),
       ruleIds = Set.unmodifiable(ruleIds) {
    if (id.isEmpty ||
        this.name.isEmpty ||
        this.name.length > 60 ||
        this.ruleIds.isEmpty ||
        this.ruleIds.any((id) => id.isEmpty)) {
      throw ArgumentError(
        'Name the profile (up to 60 characters) and select at least one activity.',
      );
    }
  }
  final String id;
  final String name;
  final Set<String> ruleIds;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'rule_ids': ruleIds.toList(),
  };
  factory FocusProfile.fromJson(Map<String, dynamic> json) => FocusProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    ruleIds: (json['rule_ids'] as List).cast<String>(),
  );
}

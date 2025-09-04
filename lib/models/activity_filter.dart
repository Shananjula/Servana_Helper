/// Activity filter (Helper perspective only — no role field)
/// Keep only statuses; easy to persist to Firestore/local prefs if you already did.
/// Usage:
///   final f = ActivityFilter.defaultForHelper();
///   f = f.copyWith(toggleStatus('open'));
class ActivityFilter {
  /// Normalized lowercase status ids (e.g., 'open', 'negotiating', 'assigned', …)
  final Set<String> statuses;

  const ActivityFilter({
    required this.statuses,
  });

  /// Reasonable defaults for the Helper app
  factory ActivityFilter.defaultForHelper() => const ActivityFilter(
    statuses: {
      'open',
      'negotiating',
      // leave the rest unchecked by default; user can enable
    },
  );

  ActivityFilter copyWith({Set<String>? statuses}) =>
      ActivityFilter(statuses: statuses ?? this.statuses);

  ActivityFilter toggleStatus(String id) {
    final next = Set<String>.from(statuses);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    return copyWith(statuses: next);
  }

  Map<String, dynamic> toMap() => {
    'statuses': statuses.toList(),
  };

  factory ActivityFilter.fromMap(Map<String, dynamic>? map) {
    if (map == null) return ActivityFilter.defaultForHelper();
    final raw = map['statuses'];
    return ActivityFilter(
      statuses: raw is List ? raw.map((e) => '$e'.toLowerCase()).toSet() : {},
    );
    // When loading old saved filters that had `role`, we silently ignore it.
  }

  @override
  String toString() => 'ActivityFilter(statuses: $statuses)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ActivityFilter && statuses.length == other.statuses.length && statuses.containsAll(other.statuses);

  @override
  int get hashCode => statuses.fold(0, (h, s) => h ^ s.hashCode);
}

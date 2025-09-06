// lib/utils/category_utils.dart
//
// Category normalization + tokens for flexible matching.
// - Posters can tag multiple categories.
// - Helpers match tasks if ANY allowed category overlaps with task tokens.
// Keep ALIAS_TO_CANON and PARENT_OF small at first, expand over time.

class CategoryMeta {
  final List<String> categoryIds;     // canonical ids (leaves or roots)
  final List<String> categoryRootIds; // parent buckets
  final List<String> categoryTokens;  // union for matching (leaves + roots + aliases)
  final String? legacyCategoryId;     // first canonical (optional legacy)
  const CategoryMeta({
    required this.categoryIds,
    required this.categoryRootIds,
    required this.categoryTokens,
    required this.legacyCategoryId,
  });
}

String _slugify(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final s = raw
      .toLowerCase()
      .normalize(NormalizationForm.NFKD)
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '') // strip accents
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return s;
}

// Aliases → canonical ids. Keep tiny & precise; expand as you see real data.
const Map<String, String> ALIAS_TO_CANON = {
  'logo_design': 'logo_branding',
  'logo&branding': 'logo_branding',
  'branding_logo': 'logo_branding',
  'math_tutor': 'tutoring_math',
  'maths_tutor': 'tutoring_math',
  'mathematics_tutor': 'tutoring_math',
};

// Leaf → parent root (taxonomy)
const Map<String, String> PARENT_OF = {
  'tutoring_math': 'tutoring',
  'tutoring_physics': 'tutoring',
  'logo_branding': 'design',
  // add more when you add categories
};

String normalizeCategoryId(String? raw) {
  final s = _slugify(raw);
  if (s.isEmpty) return '';
  return ALIAS_TO_CANON[s] ?? s;
}

CategoryMeta computeMetaForCategories(dynamic rawIds) {
  // Accept: String | List<String> | null
  final list = <String>[];
  if (rawIds is String) list.add(rawIds);
  if (rawIds is List) {
    for (final v in rawIds) {
      if (v == null) continue;
      list.add(v.toString());
    }
  }

  final canon = <String>{};
  final roots = <String>{};
  final tokens = <String>{};

  for (final r in list) {
    final c = normalizeCategoryId(r);
    if (c.isEmpty) continue;
    canon.add(c);
    final root = PARENT_OF[c] ?? c;
    roots.add(root);
    tokens.add(c);
    tokens.add(root);
    // include aliases that map to this canonical id
    ALIAS_TO_CANON.forEach((alias, target) {
      if (target == c) tokens.add(alias);
    });
  }

  final first = canon.isNotEmpty ? canon.first : null;
  return CategoryMeta(
    categoryIds: canon.toList(),
    categoryRootIds: roots.toList(),
    categoryTokens: tokens.toList(),
    legacyCategoryId: first,
  );
}

// Helper: choose a matching token between a task and a helper's allowed ids.
String? findMatchingToken({
  required Iterable<String> taskTokens,
  required Iterable<String> helperAllowedIds,
}) {
  final tokens = taskTokens.map(normalizeCategoryId).toSet();
  for (final id in helperAllowedIds) {
    final n = normalizeCategoryId(id);
    if (n.isEmpty) continue;
    if (tokens.contains(n)) return n;
  }
  return null;
}

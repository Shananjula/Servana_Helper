// lib/compat/compat_shims.dart
// Backwards-compat helpers so old code compiles without heavy refactors.

import 'package:servana/providers/user_provider.dart';

extension UserProviderCompat on UserProvider {
  /// Old code used `userProv.categories`. Map that to your current source of truth.
  /// If your provider uses another name, update it here once.
  List<String> get categories {
    // Try a few common fields; adjust to your actual provider.
    final a = ( // preferred: normalized ids, <=10
        // ignore: unnecessary_cast
        (dynamic this_).allowedCategoryIds as List<String>?
    );
    if (a != null) return a.take(10).toList();

    final b = (dynamic this_).allowed ?? [];
    if (b is List<String>) return b.take(10).toList();

    return const <String>[];
  }
}

/// Provide a deterministic integer score for "verified" ranking without breaking types.
int verifiedScore(Map<String, dynamic> m) {
  final v = (m['verified'] == true) ? 1 : 0;
  final proofsNum = m['proofCount'];
  final proofs = proofsNum is num ? proofsNum.toInt() : 0;
  // simple weight: verified first, then more proofs
  return v * 1000 + proofs.clamp(0, 999);
}

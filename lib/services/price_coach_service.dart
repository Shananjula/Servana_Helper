// lib/services/price_coach_service.dart
//
// PriceCoachService — client-side heuristic based on recent completed tasks.
// Non-breaking and optional. If the query fails, it returns null gracefully.
//
// Strategy:
//  - Query tasks where category == given category
//  - status == 'completed'
//  - createdAt within last 60 days
//  - limit 120
//  - Collect price/budget numbers, compute 25th/50th/75th percentiles
//
// NOTE: No geo filter to avoid complex composite indexes; still useful.

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';

class PriceBand {
  final int p25;
  final int p50;
  final int p75;
  const PriceBand({required this.p25, required this.p50, required this.p75});
}

class PriceCoachService {
  PriceCoachService._();
  static final PriceCoachService instance = PriceCoachService._();
  factory PriceCoachService() => instance;

  final _db = FirebaseFirestore.instance;

  Future<PriceBand?> getBandFor({
    required String category,
    String? type, // 'online'|'physical' (optional filter)
    int days = 60,
    int limit = 120,
  }) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      Query<Map<String, dynamic>> q = _db.collection('tasks')
        .where('category', isEqualTo: category)
        .where('status', isEqualTo: 'completed')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('createdAt', descending: true)
        .limit(limit);
      if (type != null && type.isNotEmpty) {
        q = q.where('type', isEqualTo: type);
      }
      final snap = await q.get();
      final vals = <num>[];
      for (final d in snap.docs) {
        final m = d.data();
        final n = (m['price'] ?? m['budget']);
        if (n is num && n > 0) vals.add(n);
      }
      if (vals.length < 6) return null; // not enough data to be useful
      vals.sort();
      int _q(double p) {
        final pos = p * (vals.length - 1);
        final lo = pos.floor();
        final hi = pos.ceil();
        if (lo == hi) return vals[lo].round();
        final w = pos - lo;
        return (vals[lo] * (1 - w) + vals[hi] * w).round();
      }
      return PriceBand(p25: _q(0.25), p50: _q(0.5), p75: _q(0.75));
    } catch (_) {
      return null;
    }
  }
}

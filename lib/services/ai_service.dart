import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight, offline-first helpers used by UI for:
///  • Smart chat actions in Conversation screen
///  • Heuristic drafting for Post Task
///  • Icon mapping for categories
///  • Price band heuristics (and record getters .min/.max)
///
/// This file intentionally has ZERO network calls so it’s always safe to use.
/// If you later wire a backend (e.g., Cloud Functions / Gemini), you can
/// replace the heuristics while keeping the same method signatures.
class AiService {
  AiService._();

  /// Suggests a contextual action in chat based on the latest user text.
  /// Returns a small payload like:
  ///   {"type":"share_contact"}
  ///   {"type":"propose_meet", "when":"today 5pm"}
  ///   {"type":"send_quote", "amount": 3500}
  /// or `null` if no suggestion.
  static Future<Map<String, dynamic>?> getSmartChatAction(String text) async {
    final t = (text).toLowerCase().trim();

    if (t.isEmpty) return null;

    // Contact exchange
    if (t.contains('phone') ||
        t.contains('whats') ||
        t.contains('contact') ||
        t.contains('number') ||
        t.contains('call me') ||
        t.contains('reach me')) {
      return {"type": "share_contact"};
    }

    // Scheduling
    if (t.contains('tomorrow') ||
        t.contains('today') ||
        t.contains('morning') ||
        t.contains('evening') ||
        t.contains('meet') ||
        t.contains('when') ||
        t.contains('what time')) {
      return {"type": "propose_meet"};
    }

    // Quoting
    if (t.contains('price') ||
        t.contains('quote') ||
        t.contains('budget') ||
        t.contains('how much')) {
      // Try to sniff an amount in the message
      final amount = _extractFirstNumber(t);
      if (amount != null) {
        return {"type": "send_quote", "amount": amount};
      }
      return {"type": "send_quote"};
    }

    // Location sharing
    if (t.contains('where') || t.contains('location') || t.contains('address')) {
      return {"type": "share_location"};
    }

    return null;
  }

  /// Drafts a task from loose text. Use when user taps "✨ Generate for me".
  /// Returns a tolerant map with any of: title, category, tags, budgetRange.
  static Future<Map<String, dynamic>> draftTaskFromText({
    String? title,
    String? description,
  }) async {
    final text = '${title ?? ''} ${description ?? ''}'.toLowerCase();

    final category = AppServices.guessCategory(text);
    final tags = AppServices.extractTags(text);
    final band = estimateBudgetBand(category: category, text: text);

    final draft = <String, dynamic>{};
    draft['title'] = _titleFrom(text) ?? (category != null ? 'Need $category' : 'New task');
    if (category != null) draft['category'] = category;
    if (tags.isNotEmpty) draft['tags'] = tags;
    if (band != null) {
      draft['budgetRange'] = {"min": band.min, "max": band.max};
    }
    return draft;
  }

  /// Very small heuristic for price band; returns a positional record (min,max).
  /// Use `.min` / `.max` thanks to [PriceBandRecordExt] below.
  static (int, int)? estimateBudgetBand({
    String? category,
    String? text,
  }) {
    final c = (category ?? AppServices.guessCategory(text ?? '') ?? '').toLowerCase();
    if (c.isEmpty) return null;

    // Extremely rough bands in LKR. Tune later if needed.
    switch (c) {
      case 'plumbing':
      case 'electrician':
        return (2500, 7500);
      case 'cleaning':
        return (1500, 4500);
      case 'moving':
      case 'delivery':
        return (3000, 12000);
      case 'painting':
        return (8000, 30000);
      case 'carpentry':
        return (5000, 20000);
      case 'gardening':
        return (2000, 6000);
      case 'ac repair':
      case 'appliance repair':
        return (4000, 15000);
      case 'graphic design':
      case 'design':
        return (5000, 20000);
      case 'it support':
      case 'computer repair':
        return (4000, 12000);
      case 'tuition':
      case 'teaching':
        return (2000, 6000);
      default:
        return (2000, 10000);
    }
  }

  // ---- private helpers ------------------------------------------------------

  static int? _extractFirstNumber(String s) {
    final m = RegExp(r'(\d[\d,\.]*)').firstMatch(s);
    if (m == null) return null;
    final raw = m.group(1)!;
    final cleaned = raw.replaceAll(',', '');
    final v = int.tryParse(cleaned.split('.').first);
    return v;
  }

  static String? _titleFrom(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;

    // Try to grab a succinct title-like phrase.
    final candidates = <String>[
      for (final part in t.split(RegExp(r'[\.!\n]'))) part.trim()
    ]..removeWhere((e) => e.isEmpty);

    if (candidates.isEmpty) return null;

    // Pick shortest meaningful piece (but not too short)
    candidates.sort((a, b) => a.length.compareTo(b.length));
    final chosen = candidates.firstWhere(
          (e) => e.length >= 8,
      orElse: () => candidates.first,
    );

    // Capitalize first letter
    return chosen[0].toUpperCase() + chosen.substring(1);
  }
}

/// Mixed utility helpers used around the app UI.
class AppServices {
  AppServices._();

  /// Map loose category text to an icon (Material defaults).
  static IconData iconFor(String? category) {
    final c = (category ?? '').toLowerCase().trim();

    if (c.contains('plumb')) return Icons.plumbing;
    if (c.contains('electric')) return Icons.electrical_services;
    if (c.contains('clean')) return Icons.cleaning_services;
    if (c.contains('paint')) return Icons.format_paint;
    if (c.contains('carp')) return Icons.chair_alt;
    if (c.contains('garden') || c.contains('yard')) return Icons.yard;
    if (c.contains('move') || c.contains('delivery')) return Icons.local_shipping;
    if (c.contains('ac') || c.contains('air')) return Icons.ac_unit;
    if (c.contains('repair') || c.contains('appliance')) return Icons.build;
    if (c.contains('design') || c.contains('graphic')) return Icons.brush;
    if (c.contains('computer') || c.contains('it')) return Icons.computer;
    if (c.contains('tuition') || c.contains('teach') || c.contains('class')) {
      return Icons.school;
    }
    return Icons.work_outline;
  }

  /// Guess a normalized category label from arbitrary text.
  static String? guessCategory(String text) {
    final t = (text).toLowerCase();

    if (t.contains('plumb')) return 'Plumbing';
    if (t.contains('electric')) return 'Electrician';
    if (t.contains('clean')) return 'Cleaning';
    if (t.contains('paint')) return 'Painting';
    if (t.contains('carp')) return 'Carpentry';
    if (t.contains('garden') || t.contains('yard')) return 'Gardening';
    if (t.contains('move') || t.contains('delivery')) return 'Delivery';
    if (t.contains('ac') || t.contains('air')) return 'AC Repair';
    if (t.contains('appliance') || t.contains('repair')) return 'Appliance Repair';
    if (t.contains('design') || t.contains('graphic')) return 'Graphic Design';
    if (t.contains('computer') || t.contains('it')) return 'IT Support';
    if (t.contains('tuition') || t.contains('teach') || t.contains('class')) return 'Tuition';
    return null;
  }

  /// Extract a few quick tags from text.
  static List<String> extractTags(String text) {
    final t = (text).toLowerCase();
    final tags = <String>{
      if (t.contains('urgent') || t.contains('asap')) 'urgent',
      if (t.contains('today')) 'today',
      if (t.contains('tomorrow')) 'tomorrow',
      if (t.contains('weekend')) 'weekend',
      if (t.contains('materials')) 'materials provided',
      if (t.contains('estimate')) 'estimate first',
      if (t.contains('onsite')) 'onsite',
      if (t.contains('remote')) 'remote',
    };
    return tags.take(5).toList();
  }

  /// Merge budgets sensibly (helper util).
  static (int, int) mergeBands((int, int) a, (int, int) b) {
    final lo = math.min(a.$1, b.$1);
    final hi = math.max(a.$2, b.$2);
    return (lo, hi);
  }
}

/// Extension so you can call `.min` / `.max` on positional record (int,int).
extension PriceBandRecordExt on (int, int) {
  int get min => $1;
  int get max => $2;
}

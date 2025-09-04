// lib/widgets/status_chip.dart
//
// A tolerant status pill that maps common task/offer statuses
// to accessible colors. Unknown statuses fall back to a neutral chip.
//
// Supported canonical statuses (case/spacing/dash-insensitive):
// - open / listed
// - negotiating / negotiation
// - assigned / booked / scheduled
// - en_route / enroute
// - arrived
// - in_progress / started / ongoing
// - pending_completion / pending_payment / pending_rating
// - completed / finished / closed / rated
// - cancelled / canceled
// - in_dispute / disputed / dispute
//
// Usage:
//   StatusChip('in_progress')

import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final norm = _normalize(status);
    final style = _styleFor(norm, cs, theme.brightness);

    // Fallback label: readable and compact
    final label = style.label ?? (status.isEmpty ? '—' : status.replaceAll('_', ' ').toUpperCase());

    return Semantics(
      label: '$label status',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: style.border ?? style.bg.withOpacity(0.0)),
        ),
        child: DefaultTextStyle(
          style: theme.textTheme.labelSmall?.copyWith(
            color: style.fg,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ) ??
              TextStyle(
                color: style.fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Normalize input to a compact token we can map:
/// - lowercased
/// - non-letters collapsed to underscores
/// - trim leading/trailing underscores
String _normalize(String raw) {
  final s = (raw.isEmpty ? '' : raw).toLowerCase();
  final collapsed = s.replaceAll(RegExp(r'[^a-z]+'), '_');
  final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  return trimmed;
}

class _ChipStyle {
  const _ChipStyle({required this.bg, required this.fg, this.label, this.border});
  final Color bg;
  final Color fg;
  final String? label;
  final Color? border;
}

_ChipStyle _styleFor(String norm, ColorScheme cs, Brightness brightness) {
  // Helpers
  Color mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

  // Themed semantic colors
  final green = const Color(0xFF2E7D32); // accessible green on light
  final greenDark = const Color(0xFF66BB6A);
  final amber = const Color(0xFFFFA000);
  final amberDark = const Color(0xFFFFD54F);

  // Neutral fallback
  final neutralBg = brightness == Brightness.light
      ? mix(cs.surface, cs.outlineVariant, 0.08)
      : mix(cs.surfaceVariant, cs.outlineVariant, 0.20);
  final neutralBorder = cs.outline.withOpacity(brightness == Brightness.light ? 0.30 : 0.40);
  final neutralFg = cs.onSurfaceVariant;

  switch (norm) {
  // Primary “positive / actionable”
    case 'open':
    case 'listed':
      return _ChipStyle(bg: cs.primary, fg: cs.onPrimary, label: 'OPEN');

    case 'negotiating':
    case 'negotiation':
      return _ChipStyle(
        bg: brightness == Brightness.light ? amber : amberDark,
        fg: Colors.black,
        label: 'NEGOTIATING',
      );

    case 'assigned':
    case 'booked':
    case 'scheduled':
      return _ChipStyle(
        bg: cs.primaryContainer,
        fg: cs.onPrimaryContainer,
        label: 'ASSIGNED',
        border: cs.primary.withOpacity(0.20),
      );

    case 'en_route':
    case 'enroute':
      return _ChipStyle(
        bg: cs.secondary,
        fg: cs.onSecondary,
        label: 'EN ROUTE',
      );

    case 'arrived':
      return _ChipStyle(
        bg: brightness == Brightness.light ? green : greenDark,
        fg: Colors.white,
        label: 'ARRIVED',
      );

    case 'in_progress':
    case 'started':
    case 'ongoing':
      return _ChipStyle(
        bg: brightness == Brightness.light ? green : greenDark,
        fg: Colors.white,
        label: 'IN PROGRESS',
      );

    case 'pending_completion':
      return _ChipStyle(
        bg: brightness == Brightness.light ? amber : amberDark,
        fg: Colors.black,
        label: 'PENDING COMPLETION',
      );

    case 'pending_payment':
      return _ChipStyle(
        bg: brightness == Brightness.light ? amber : amberDark,
        fg: Colors.black,
        label: 'PENDING PAYMENT',
      );

    case 'pending_rating':
      return _ChipStyle(
        bg: brightness == Brightness.light ? amber : amberDark,
        fg: Colors.black,
        label: 'PENDING RATING',
      );

    case 'completed':
    case 'finished':
    case 'closed':
      return _ChipStyle(
        bg: neutralBg,
        fg: neutralFg,
        label: 'COMPLETED',
        border: neutralBorder,
      );

    case 'rated':
      return _ChipStyle(
        bg: cs.tertiaryContainer,
        fg: cs.onTertiaryContainer,
        label: 'RATED',
        border: cs.tertiary.withOpacity(0.20),
      );

    case 'cancelled':
    case 'canceled':
      return _ChipStyle(bg: cs.error, fg: cs.onError, label: 'CANCELLED');

    case 'in_dispute':
    case 'disputed':
    case 'dispute':
      return _ChipStyle(
        bg: cs.errorContainer,
        fg: cs.onErrorContainer,
        label: 'IN DISPUTE',
        border: cs.error.withOpacity(0.30),
      );

    default:
    // Neutral fallback for unknown statuses
      final display = norm.isEmpty ? '—' : norm.replaceAll('_', ' ').toUpperCase();
      return _ChipStyle(
        bg: neutralBg,
        fg: neutralFg,
        label: display,
        border: neutralBorder,
      );
  }
}

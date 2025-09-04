import 'package:flutter/material.dart';

/// A rounded pill that renders monetary amounts in LKR with thousands
/// separators. If [amount] is null, falls back to [text], then "—".
///
/// Examples:
///   AmountPill(amount: 12500);          // LKR 12,500
///   AmountPill(amount: 1999.5);         // LKR 1,999.50
///   AmountPill(text: 'Free');           // Free
///   AmountPill();                       // —
///
/// Styling adapts to Material 3 color scheme and dark mode automatically.
class AmountPill extends StatelessWidget {
  const AmountPill({
    super.key,
    this.amount,
    this.text,
    this.background,
    this.foreground,
    this.padding,
  });

  /// Amount in Sri Lankan Rupees. If provided, takes precedence over [text].
  final num? amount;

  /// Fallback text (e.g., "Free", "Negotiable") when [amount] is null.
  final String? text;

  /// Optional override for background color.
  final Color? background;

  /// Optional override for text color.
  final Color? foreground;

  /// Optional override for internal padding.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String display = amount != null
        ? _formatLkr(amount!)
        : (text == null || text!.trim().isEmpty ? '—' : text!.trim());

    // Use a calm container tone so it works well as a trailing widget.
    final Color bg =
        background ?? cs.primaryContainer.withOpacity(theme.brightness == Brightness.light ? 1.0 : 0.95);
    final Color fg = foreground ?? cs.onPrimaryContainer;

    return Semantics(
      label: amount != null ? 'Amount $display' : 'Value $display',
      readOnly: true,
      child: Container(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: cs.primary.withOpacity(0.20),
            width: 1,
          ),
        ),
        child: DefaultTextStyle(
          style: theme.textTheme.labelSmall?.copyWith(
            color: fg,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ) ??
              TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
          child: Text(
            display,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Lightweight LKR formatter without relying on intl.
/// Produces "LKR 12,345" or "LKR 1,234.50" depending on fractional part.
String _formatLkr(num n) {
  final negative = n < 0;
  final abs = n.abs();

  // Choose decimals: none for whole numbers, 2 for fractional.
  final bool isWhole = abs % 1 == 0;
  final String raw = isWhole ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);

  // Insert thousands separators.
  final parts = raw.split('.');
  String whole = parts[0];
  final String frac = parts.length > 1 ? parts[1] : '';

  final reg = RegExp(r'\B(?=(\d{3})+(?!\d))');
  whole = whole.replaceAllMapped(reg, (m) => ',');

  final prefix = negative ? '−' : '';
  return frac.isEmpty ? 'LKR $prefix$whole' : 'LKR $prefix$whole.$frac';
}

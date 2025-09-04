import 'package:flutter/material.dart';

/// A modern, Uber-like icon tile with:
/// - Large icon in a tinted circular backdrop
/// - Short label
/// - Rounded 16dp card with ripple
/// - Optional small badge pill (e.g., "New", "3")
///
/// Usage:
/// IconTile(
///   icon: Icons.post_add_rounded,
///   label: 'Post task',
///   badge: 'New',
///   onTap: () {},
/// )
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    // Card/surface color & border tuned for M3 without relying on experimental tokens.
    final Color tileColor =
    isLight ? cs.surface : cs.surfaceVariant.withOpacity(0.35);
    final Color borderColor = cs.outline.withOpacity(isLight ? 0.12 : 0.18);

    // Icon backdrop tint
    final Color iconBg = cs.primary.withOpacity(isLight ? 0.12 : 0.20);
    final Color iconFg = cs.primary;

    final radius = BorderRadius.circular(16);

    return Semantics(
      // Mark as button only if interactive.
      button: onTap != null,
      label: label,
      child: ConstrainedBox(
        // Ensure generous tap target and good grid feel on small screens.
        constraints: const BoxConstraints(minWidth: 88, minHeight: 96),
        child: Material(
          color: tileColor,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Stack(
              children: [
                // Content
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon with tinted circular backdrop
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: iconBg,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            icon,
                            color: iconFg,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Label
                        Tooltip(
                          message: label,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Optional badge pill (top-right)
                if (badge != null && badge!.trim().isNotEmpty)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _BadgePill(text: badge!.trim()),
                  ),

                // Focus ring for accessibility (visible focus on keyboard nav)
                Positioned.fill(
                  child: Focus(
                    descendantsAreFocusable: false,
                    child: Builder(
                      builder: (context) {
                        final focused = Focus.of(context).hasPrimaryFocus;
                        return IgnorePointer(
                          ignoring: true,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              borderRadius: radius,
                              boxShadow: focused
                                  ? [
                                BoxShadow(
                                  color: cs.primary.withOpacity(0.25),
                                  blurRadius: 10,
                                  spreadRadius: 0,
                                ),
                              ]
                                  : const [],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    final bg = cs.primary;
    final fg = isLight ? Colors.white : cs.onPrimary;

    return Container(
      constraints: const BoxConstraints(minHeight: 22, minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

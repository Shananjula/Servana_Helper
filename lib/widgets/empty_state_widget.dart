// lib/widgets/empty_state_widget.dart
//
// Reusable empty-state widget used across screens
// • Configurable icon, title, message
// • Optional primary action (label + onPressed)
// • Optional secondary action
//
// Usage:
//   const EmptyStateWidget(
//     icon: Icons.inbox_outlined,
//     title: 'No posts',
//     message: 'Create your first task to get started.',
//     primaryLabel: 'Post a task',
//     onPrimaryPressed: _goPost,
//   );

import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;

  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;

  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  /// If true, uses smaller paddings (handy inside Cards)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = compact ? const EdgeInsets.all(12) : const EdgeInsets.all(24);
    final iconSize = compact ? 36.0 : 44.0;
    final gap = compact ? 8.0 : 10.0;

    return Center(
      child: Padding(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: cs.outline),
            SizedBox(height: gap),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (primaryLabel != null || secondaryLabel != null) ...[
              SizedBox(height: compact ? 10 : 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (primaryLabel != null)
                    FilledButton(
                      onPressed: onPrimaryPressed,
                      child: Text(primaryLabel!),
                    ),
                  if (secondaryLabel != null)
                    OutlinedButton(
                      onPressed: onSecondaryPressed,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

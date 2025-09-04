import 'package:flutter/material.dart';
import '../models/activity_filter.dart';

/// Bottom sheet UI for filtering Activity (no role chips)
/// Call with:
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => ActivityFilterSheet(
///     initial: currentFilter,
///     onApply: (f) { setState(() => currentFilter = f); },
///     onClear: () { setState(() => currentFilter = ActivityFilter.defaultForHelper()); },
///   ),
/// );
class ActivityFilterSheet extends StatefulWidget {
  final ActivityFilter initial;
  final ValueChanged<ActivityFilter> onApply;
  final VoidCallback? onClear;

  const ActivityFilterSheet({
    super.key,
    required this.initial,
    required this.onApply,
    this.onClear,
  });

  @override
  State<ActivityFilterSheet> createState() => _ActivityFilterSheetState();
}

class _ActivityFilterSheetState extends State<ActivityFilterSheet> {
  late ActivityFilter _filter;

  // All statuses we support in UI. Keys = normalized ids; values = pretty labels.
  static const Map<String, String> kStatusLabels = {
    'open': 'OPEN',
    'negotiating': 'NEGOTIATING',
    'assigned': 'ASSIGNED',
    'en_route': 'En route',
    'arrived': 'ARRIVED',
    'in_progress': 'In progress',
    'pending_completion': 'Pending completion',
    'pending_payment': 'Pending payment',
    'pending_rating': 'Pending rating',
    'closed': 'CLOSED',
    'rated': 'RATED',
    'cancelled': 'CANCELLED',
    'in_dispute': 'In dispute',
  };

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = kStatusLabels.entries.map((e) {
      final id = e.key;
      final label = e.value;
      final selected = _filter.statuses.contains(id);
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() {
            _filter = _filter.toggleStatus(id);
          }),
        ),
      );
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44, height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            Text('Filter activity', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),

            // 🚫 Role section removed.

            Text('Statuses', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(children: chips),

            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    final def = ActivityFilter.defaultForHelper();
                    setState(() => _filter = def);
                    widget.onClear?.call();
                  },
                  child: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    widget.onApply(_filter);
                    Navigator.of(context).maybePop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

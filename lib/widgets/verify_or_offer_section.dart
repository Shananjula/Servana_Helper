
// lib/widgets/verify_or_offer_section.dart
//
// Drop-in widget to show either:
//  - "Verify" banner with correct reason (basic docs vs category)
//  - OR nothing (so you can show your existing Make Offer actions)
//
// Usage in Task Details screen (where you have taskId & task map):
//   VerifyOrOfferSection(
//     taskId: taskId,
//     task: taskMap,
//     onMakeOffer: () => _openOfferBottomSheet(taskId, taskMap), // your existing function
//     onVerifyBasicDocs: () => Navigator.pushNamed(context, '/verify/basic'), // optional
//     onVerifyCategory: (catId) => Navigator.pushNamed(context, '/verify/category', arguments: catId), // optional
//   );
//
// If you want the widget to include the button too, set includeOfferButton: true
// and provide onMakeOffer. Otherwise it will just render the banner (or nothing).

import 'package:flutter/material.dart';
import 'package:servana/services/eligibility_service.dart' as elig;

class VerifyOrOfferSection extends StatelessWidget {
  final String taskId;
  final Map<String, dynamic> task;
  final VoidCallback? onMakeOffer;
  final bool includeOfferButton;

  /// Optional navigation callbacks. If null, tapping will just show a SnackBar.
  final VoidCallback? onVerifyBasicDocs;
  final void Function(String categoryId)? onVerifyCategory;

  const VerifyOrOfferSection({
    super.key,
    required this.taskId,
    required this.task,
    this.onMakeOffer,
    this.includeOfferButton = false,
    this.onVerifyBasicDocs,
    this.onVerifyCategory,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<elig.CategoryEligibility>(
      future: elig.EligibilityService().checkHelperEligibilityForTask(task),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (!snap.hasData) return const SizedBox.shrink();
        final e = snap.data!;

        if (e.isAllowed) {
          // Allowed -> either render nothing (let your existing offer UI show),
          // or render the button if includeOfferButton=true.
          if (!includeOfferButton) return const SizedBox.shrink();
          return _OfferButton(onPressed: onMakeOffer);
        }

        // Not allowed -> show reasoned banner + Verify button
        final isBasic = e.reason == 'basic_docs';
        final title = isBasic
            ? 'Verify basic documents to make offers on physical tasks.'
            : 'Verify for ${_pretty(e.categoryId)} to make offers.';

        return _BannerCard(
          title: title,
          action: TextButton.icon(
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Verify now'),
            onPressed: () {
              if (isBasic) {
                if (onVerifyBasicDocs != None && onVerifyBasicDocs != null) {
                  onVerifyBasicDocs!();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Navigate to your Basic Docs screen')),
                  );
                }
              } else {
                if (onVerifyCategory != null) {
                  onVerifyCategory!(e.categoryId);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Navigate to category verification: ${_pretty(e.categoryId)}')),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }

  static String _pretty(String id) {
    if (id.trim().isEmpty) return id;
    return id.replaceAll('_', ' ').splitMapJoin(
      RegExp(r'\b\w'),
      onMatch: (m) => m.group(0)!.toUpperCase(),
      onNonMatch: (n) => n,
    );
  }
}

class _OfferButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _OfferButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.local_offer_outlined),
        label: const Text('Make an offer'),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final String title;
  final Widget? action;
  const _BannerCard({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          if (action != null) action!,
        ],
      ),
    );
  }
}

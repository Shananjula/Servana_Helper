import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:servana/models/task_model.dart';
import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/services/firestore_service.dart';
import 'package:servana/utils/verification_nav.dart';
import 'package:servana/screens/step_2_documents.dart' as step2;
import 'package:servana/config/economy_config.dart';
import 'package:servana/screens/top_up_screen.dart';

class RecommendedTaskCard extends StatelessWidget {
  const RecommendedTaskCard({super.key, required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final nf = NumberFormat("#,##0");

    final String title = task.title ?? 'Task';
    final num? pay = task.price ?? task.budget;
    final String payText = (pay == null) ? '—' : 'LKR ${nf.format(pay)}';

    return SizedBox(
      width: 260,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: task.id)));
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.payments_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(payText, style: theme.textTheme.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (pay != null) _FeeHint(pay: pay),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.local_offer_rounded, size: 18),
                    label: const Text('Apply'),
                    onPressed: () async {
                      // Verification guard: ensure eligible for task.category
                      final okEligible = await VerificationNav.ensureEligibleOrRedirect(context, task.category);
                      if (!okEligible) return;
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      final ok = await FirestoreService.instance.hasMinCoinsToApply(
                        uid, minCoins: EconomyConfig.minApplyCoins,
                      );
                      if (!ok) {
                        _showGateDialog(context);
                        return;
                      }
                      Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: task.id)));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGateDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You need more coins', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('At least ${EconomyConfig.minApplyCoins} coins are required to apply for tasks.',
              style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Browse only'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.account_balance_wallet_rounded),
                    label: const Text('Top up'),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const TopUpScreen()));
                    },
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _FeeHint extends StatelessWidget {
  const _FeeHint({required this.pay});
  final num pay;

  @override
  Widget build(BuildContext context) {
    final fee = FirestoreService.instance.commissionCoinsForPrice(
      pay, pct: EconomyConfig.platformFeePct,
    );
    return Tooltip(
      message: 'Est. commission • ${EconomyConfig.platformFeePct}%',
      child: Chip(
        visualDensity: VisualDensity.compact,
        label: Text('~${fee} coins', style: Theme.of(context).textTheme.labelSmall),
        avatar: const Icon(Icons.offline_bolt_rounded, size: 14),
      ),
    );
  }
}

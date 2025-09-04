// lib/screens/rating_screen.dart
//
// Leave a Review (both roles)
// • Called after a task is completed (or from a profile “Write a review” CTA)
// • Collects: star rating (0.5–5.0), short comment (optional), anonymity toggle
// • Writes to: reviews/{autoId}  and softly updates the target user’s rating counters
// • If taskId provided → also writes tasks/{taskId}.reviewedBy{Poster|Helper}=true
//
// Firestore schemas used (guarded):
//   reviews/{id} {
//     taskId?: string,
//     reviewerId: uid,
//     revieweeId: uid,
//     role: 'poster'|'helper',        // reviewee role
//     rating: number (0.5..5),
//     comment?: string,
//     anonymous?: bool,
//     createdAt: Timestamp
//   }
//
//   users/{revieweeId} aggregates (soft, non-authoritative; backend should reconcile):
//     averageRating: number
//     ratingCount: number
//
// Notes:
// • We use a transaction to apply a running average. In a high-write environment,
//   move aggregation to Cloud Functions. This is a safe, client-friendly fallback.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({
    super.key,
    required this.revieweeId,
    this.taskId,
    this.revieweeRole = 'helper', // 'helper' | 'poster'
  });

  final String revieweeId;
  final String? taskId;
  final String revieweeRole;

  // New factory for easily creating a helper review screen
  factory RatingScreen.helper({Key? key, required String helperId, String? taskId}) {
    return RatingScreen(key: key, revieweeId: helperId, revieweeRole: 'helper', taskId: taskId);
  }

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  double _rating = 5.0;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _anonymous = false;
  bool _busy = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      _toast('Please sign in first.', error: true);
      return;
    }
    if (_rating <= 0) {
      _toast('Please choose a rating.');
      return;
    }

    setState(() => _busy = true);

    try {
      final now = FieldValue.serverTimestamp();

      // 1) Create the review document
      final revRef = FirebaseFirestore.instance.collection('reviews').doc();
      await revRef.set({
        'taskId': widget.taskId,
        'reviewerId': me.uid,
        'revieweeId': widget.revieweeId,
        'role': widget.revieweeRole, // reviewee role
        'rating': _rating,
        'comment': _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
        'anonymous': _anonymous,
        'createdAt': now,
      });

      // 2) Soft aggregate on reviewee user doc using a transaction
      final userRef = FirebaseFirestore.instance.collection('users').doc(widget.revieweeId);
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(userRef);
        final m = (snap.data() ?? <String, dynamic>{});
        final prevCount = (m['ratingCount'] is num) ? (m['ratingCount'] as num).toInt() : 0;
        final prevAvg = (m['averageRating'] is num) ? (m['averageRating'] as num).toDouble() : 0.0;

        final nextCount = prevCount + 1;
        final nextAvg = ((prevAvg * prevCount) + _rating) / (nextCount == 0 ? 1 : nextCount);

        trx.set(userRef, {
          'ratingCount': nextCount,
          'averageRating': double.parse(nextAvg.toStringAsFixed(2)),
          'updatedAt': now,
        }, SetOptions(merge: true));
      });

      // 3) Mark task as reviewed (optional)
      if (widget.taskId != null && widget.taskId!.isNotEmpty) {
        final taskRef = FirebaseFirestore.instance.collection('tasks').doc(widget.taskId);
        await taskRef.set({
          widget.revieweeRole == 'helper' ? 'reviewedByPoster' : 'reviewedByHelper': true,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      _toast('Thanks for your feedback!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _toast('Could not submit review: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave a review'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          // Header
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primary.withOpacity(0.12),
                foregroundColor: cs.primary,
                child: const Icon(Icons.rate_review_outlined),
              ),
              title: Text('Review the ${widget.revieweeRole == 'helper' ? 'helper' : 'poster'}'),
              subtitle: Text('User: ${widget.revieweeId.substring(0, 6)}…'),
            ),
          ),
          const SizedBox(height: 12),

          // Stars
          _Stars(
            value: _rating,
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 12),

          // Comment
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: TextField(
                controller: _commentCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  hintText: 'What went well? Anything to improve?',
                ),
              ),
            ),
          ),

          // Anonymous toggle
          SwitchListTile(
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: const Text('Post anonymously'),
            subtitle: const Text('Your name won’t be shown with this review.'),
            secondary: const Icon(Icons.visibility_off_outlined),
          ),

          // Info
          Card(
            color: cs.surfaceContainerHigh,
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Be honest and respectful.'),
              subtitle: Text('Reviews help everyone make better decisions.'),
            ),
          ),
        ],
      ),

      // Submit bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_outlined),
            label: const Text('Submit review'),
          ),
        ),
      ),
    );
  }
}

// ---------------- Stars widget ----------------

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // 10 tappable segments (0.5 steps)
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rating: ${value.toStringAsFixed(1)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: List.generate(10, (i) {
                final step = (i + 1) * 0.5;
                final filled = value >= step;
                return InkWell(
                  onTap: () => onChanged(step),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: filled ? Colors.amber : Colors.grey,
                    size: 28,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

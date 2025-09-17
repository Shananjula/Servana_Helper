// lib/widgets/offer_button.dart
//
// Drop-in Offer button that honors category verification gating using UserGateService.
// Usage:
//   OfferButton(
//     task: t,            // Map<String, dynamic> task document data
//     taskId: tId,        // (optional) task id
//     onOfferTap: () { /* open offer composer */ },
//     onVerifyTap: () { /* open verification flow screen */ },
//   )
//
// Make sure main.dart provides UserGateService at the top of the widget tree:
//   ChangeNotifierProvider(create: (_) => UserGateService())
//
// Requires: provider, cloud_firestore, firebase_auth, firebase_functions

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/user_gate_service.dart';

class OfferButton extends StatelessWidget {
  final Map<String, dynamic> task;
  final String? taskId;
  final VoidCallback? onOfferTap;
  final VoidCallback? onVerifyTap;
  final bool fullWidth;

  const OfferButton({
    super.key,
    required this.task,
    this.taskId,
    this.onOfferTap,
    this.onVerifyTap,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UserGateService>(builder: (context, gate, _) {
      final child = _buildInner(context, gate);
      if (fullWidth) {
        return SizedBox(width: double.infinity, child: child);
      }
      return child;
    });
  }

  Widget _buildInner(BuildContext context, UserGateService gate) {
    if (!gate.ready) {
      return FilledButton.tonal(
        onPressed: null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
              height: 16, width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Loading…'),
          ],
        ),
      );
    }

    final can = gate.canOfferForTask(task);
    if (can) {
      return FilledButton.icon(
        onPressed: onOfferTap ?? () { _fallbackSnack(context, 'Open offer composer'); },
        icon: const Icon(Icons.handshake),
        label: const Text('Make an offer'),
      );
    }

    return OutlinedButton.icon(
      onPressed: onVerifyTap ?? () { _fallbackSnack(context, 'Open verification'); },
      icon: const Icon(Icons.verified_user),
      label: const Text('Verify category to offer'),
    );
  }

  void _fallbackSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
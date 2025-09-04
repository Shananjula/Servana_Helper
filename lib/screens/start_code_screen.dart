// lib/screens/start_code_screen.dart
//
// Poster-facing screen to display a 6‑digit Start Code for a task.
// The code is stored on the task doc as `startKey` (with `startKeyIssuedAt`).
// Helper must enter the same code to start the job.
//
// No QR deps. Code is large and copyable; you can add qr_flutter later.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:servana/services/firestore_service.dart';

class StartCodeScreen extends StatefulWidget {
  const StartCodeScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<StartCodeScreen> createState() => _StartCodeScreenState();
}

class _StartCodeScreenState extends State<StartCodeScreen> {
  String? _code;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ensureCode();
  }

  Future<void> _ensureCode() async {
    setState(() => _busy = true);
    try {
      final c = await FirestoreService().issueStartKey(widget.taskId);
      if (mounted) setState(() => _code = c);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _regenerate() async {
    if (_busy) return;
    await _ensureCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Start code')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? const <String, dynamic>{};
          final code = (data['startKey'] ?? _code ?? '') as String;
          final issuedAt = data['startKeyIssuedAt'];
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Ask the helper to enter this code on their phone to start the job:', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black12),
                      color: Colors.black.withOpacity(.02),
                    ),
                    child: SelectableText(
                      code.isEmpty ? '••••••' : code,
                      style: const TextStyle(fontSize: 44, letterSpacing: 6, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (issuedAt != null) Text('Issued just now', style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _busy ? null : _regenerate,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Regenerate'),
                  ),
                  const SizedBox(height: 10),
                  Text('For security, the code may change when regenerated.', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

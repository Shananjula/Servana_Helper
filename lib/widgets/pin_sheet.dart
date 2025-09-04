// lib/widgets/pin_sheet.dart
//
// PIN Sheet — Start/Finish with 4-digit code (shared for helper & poster)
// - If task has startPin/finishPin, validates against it.
// - If not set, accepts any 4-digit and stores it as pinStartEntered/pinFinishEntered.
// - Updates task status + timestamps.
//
// Usage:
//   final ok = await showPinSheet(context, mode: PinMode.start, taskId: taskId);
//
// Firestore:
//   tasks/{taskId} {
//     startPin?: string, finishPin?: string,
//     pinStartEntered?: string, pinFinishEntered?: string,
//     status, startedAt, finishedAt, updatedAt
//   }

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum PinMode { start, finish }

Future<bool?> showPinSheet(
    BuildContext context, {
      required PinMode mode,
      required String taskId,
    }) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PinSheet(mode: mode, taskId: taskId),
  );
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.mode, required this.taskId});
  final PinMode mode;
  final String taskId;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _pin = TextEditingController();
  bool _busy = false;
  String? _expected;

  @override
  void initState() {
    super.initState();
    _loadExpected();
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _loadExpected() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).get();
      final data = doc.data() ?? {};
      setState(() {
        _expected = widget.mode == PinMode.start
            ? (data['startPin']?.toString())
            : (data['finishPin']?.toString());
      });
    } catch (_) {
      // keep null → accept any 4-digit and store it
    }
  }

  Future<void> _commit() async {
    final raw = _pin.text.trim();
    if (raw.length != 4 || int.tryParse(raw) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a 4-digit PIN')));
      return;
    }

    setState(() => _busy = true);
    try {
      final ref = FirebaseFirestore.instance.collection('tasks').doc(widget.taskId);
      final now = FieldValue.serverTimestamp();

      // Validate if expected is set
      if (_expected != null && _expected!.isNotEmpty && _expected != raw) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect PIN')));
        setState(() => _busy = false);
        return;
      }

      if (widget.mode == PinMode.start) {
        await ref.set({
          'status': 'ongoing',
          'startedAt': now,
          if (_expected == null || _expected!.isEmpty) 'pinStartEntered': raw,
          'updatedAt': now,
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'status': 'completed',
          'finishedAt': now,
          if (_expected == null || _expected!.isEmpty) 'pinFinishEntered': raw,
          'updatedAt': now,
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.mode == PinMode.start ? 'Start PIN' : 'Finish PIN';
    final hint = _expected == null || _expected!.isEmpty ? '$label (set by helper or ops)' : label;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: hint, border: const OutlineInputBorder(), counterText: ''),
              onSubmitted: (_) => _commit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_rounded),
                    label: const Text('Confirm'),
                    onPressed: _busy ? null : _commit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

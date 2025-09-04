// lib/screens/availability_screen.dart
//
// Helpers set weekly availability windows. Stored in users/{uid}.availability
// as an array of { day: 0..6 (Mon..Sun), from: 'HH:mm', to: 'HH:mm' }.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});
  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  final Map<int, List<(TimeOfDay from, TimeOfDay to)>> _week = {
    for (int d = 0; d < 7; d++) d: <(TimeOfDay, TimeOfDay)>[],
  };
  bool _loaded = false;
  bool _saving = false;

  static const _days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = snap.data() ?? {};
    final avail = (data['availability'] is List) ? List<Map<String, dynamic>>.from(data['availability']) : const <Map<String, dynamic>>[];
    for (final m in avail) {
      final day = (m['day'] is num) ? (m['day'] as num).toInt() : 0;
      final fromStr = (m['from'] ?? '09:00') as String;
      final toStr = (m['to'] ?? '18:00') as String;
      final from = _parse(fromStr);
      final to = _parse(toStr);
      if (_week.containsKey(day)) {
        _week[day]!.add((from, to));
      }
    }
    setState(() => _loaded = true);
  }

  TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts[0]) ?? 9;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) => t.hour.toString().padLeft(2, '0') + ':' + t.minute.toString().padLeft(2, '0');

  Future<void> _addSlot(int day) async {
    final from = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (from == null) return;
    final to = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
    if (to == null) return;
    setState(() => _week[day]!.add((from, to)));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final arr = <Map<String, dynamic>>[];
      _week.forEach((day, slots) {
        for (final s in slots) {
          arr.add({'day': day, 'from': _fmt(s.$0), 'to': _fmt(s.$1)});
        }
      });
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'availability': arr,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Availability saved.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Availability'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.save_outlined),
            label: const Text('Save'),
          )
        ],
      ),
      body: ListView.builder(
        itemCount: 7,
        itemBuilder: (context, i) {
          final slots = _week[i]!;
          return Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(_days[i], style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton.icon(onPressed: () => _addSlot(i), icon: const Icon(Icons.add), label: const Text('Add slot')),
                    ],
                  ),
                  if (slots.isEmpty) const Text('No slots added.'),
                  for (int s = 0; s < slots.length; s++)
                    Row(
                      children: [
                        Expanded(child: Text('${_fmt(slots[s].$0)} – ${_fmt(slots[s].$1)}')),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => slots.removeAt(s))),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

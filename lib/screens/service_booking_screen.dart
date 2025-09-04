// lib/screens/service_booking_screen.dart
//
// Book a Helper’s Service (Poster)
// • Opens from: HelperPublicProfileScreen (Contact → Book) or Services list
// • Collects: date & time window, task type (Physical/Online), address (if physical),
//   budget (LKR), notes, and optional service reference
// • Creates a new task targeted to the helper (targetHelperId) with status 'open'
// • Wallet gate: requires min balance (e.g., LKR 200) -> route to TopUpScreen if short
// • After create: opens TaskDetailsScreen and optionally the chat thread
//
// Firestore schema used (guarded):
//   tasks/{taskId} {
//     title, description, category, type:'online'|'physical',
//     posterId, targetHelperId, status:'open',
//     price, schedule: {date, start, end},
//     lat?, lng?, address?,
//     createdAt, updatedAt
//   }
//
// Optional integrations (best-effort):
//   - Create / reuse chat channel with helper and post a “booking request” message
//   - Send FCM via a Cloud Function 'notifyBookingRequest' (safe try/catch)
//
// Safe fallbacks: all writes are merge-friendly; null/empty values are tolerated.

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/screens/top_up_screen.dart';
import 'package:servana/screens/map_picker_screen.dart';
import 'package:servana/screens/task_details_screen.dart';
import 'package:servana/screens/conversation_screen.dart';

class ServiceBookingScreen extends StatefulWidget {
  const ServiceBookingScreen({
    super.key,
    required this.helperId,
    this.serviceId,
    this.presetCategory,
  });

  /// The helper being booked
  final String helperId;

  /// Optional specific service the user tapped
  final String? serviceId;

  /// Optional normalized category (e.g., 'cleaning', 'tutoring')
  final String? presetCategory;

  @override
  State<ServiceBookingScreen> createState() => _ServiceBookingScreenState();
}

class _ServiceBookingScreenState extends State<ServiceBookingScreen> {
  // --- Config ---
  static const int _minPostingBalanceLkr = 200;

  // --- Form Controllers ---
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _type = 'physical'; // 'physical' | 'online'
  String? _category;         // normalized ID (optional)
  double? _lat;
  double? _lng;

  bool _busy = false;
  int _wallet = 0;

  @override
  void initState() {
    super.initState();
    _category = widget.presetCategory;
    _primeWallet();
    _titleCtrl.text = 'Booking request';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _dateCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _primeWallet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final m = doc.data() ?? {};
      setState(() {
        final w = m['walletBalance'];
        _wallet = w is int ? w : w is num ? w.toInt() : 0;
      });
    } catch (_) {}
  }

  // --- Pickers ---

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: now,
    );
    if (picked != null) {
      _dateCtrl.text = '${picked.year}-${_2(picked.month)}-${_2(picked.day)}';
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) ctrl.text = _fmtTime(picked);
  }

  Future<void> _pickLocation() async {
    final res = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen(title: 'Pick job location')),
    );
    if (res != null) {
      final dlat = (res['lat'] as num?)?.toDouble();
      final dlng = (res['lng'] as num?)?.toDouble();
      final addr = (res['address'] ?? '') as String;
      setState(() {
        _lat = dlat;
        _lng = dlng;
        _addressCtrl.text = addr;
      });
    }
  }

  // --- Submit ---

  Future<void> _createBooking() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _toast('Please sign in first.');
      return;
    }

    // Wallet gate
    if (_wallet < _minPostingBalanceLkr) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Add balance to continue'),
          content: Text('You need at least LKR $_minPostingBalanceLkr to book a helper. Top up now?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Top up')),
          ],
        ),
      );
      if (ok == true) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const TopUpScreen()));
        await _primeWallet();
      }
      return;
    }

    if (_type == 'physical' && (_lat == null || _lng == null)) {
      _toast('Please pick a location for physical bookings.');
      return;
    }

    setState(() => _busy = true);

    try {
      // Build schedule + payload
      final schedule = <String, dynamic>{
        if (_dateCtrl.text.trim().isNotEmpty) 'date': _dateCtrl.text.trim(),
        if (_startCtrl.text.trim().isNotEmpty) 'start': _startCtrl.text.trim(),
        if (_endCtrl.text.trim().isNotEmpty) 'end': _endCtrl.text.trim(),
      };

      final payload = <String, dynamic>{
        'title': _titleCtrl.text.trim().isEmpty ? 'Booking request' : _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
        'type': _type, // 'online'|'physical'
        'status': 'open',
        'posterId': uid,
        'targetHelperId': widget.helperId,
        'price': num.tryParse(_priceCtrl.text.trim()) ?? 0,
        'schedule': schedule,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        if (_addressCtrl.text.trim().isNotEmpty) 'address': _addressCtrl.text.trim(),
        if (widget.serviceId != null) 'serviceId': widget.serviceId,
        'booking': {'direct': true}, // flag to distinguish from public posts
      };

      final taskRef = await FirebaseFirestore.instance.collection('tasks').add(payload);
      final taskId = taskRef.id;

      // Create / reuse chat and drop a message
      final channelId = _channelId(uid, widget.helperId);
      await _ensureChat(channelId, uid, widget.helperId, taskId);
      await _postBookingMessage(channelId, taskId);

      // Optional: inform backend to send push
      await _tryNotify(widget.helperId, taskId);

      if (!mounted) return;
      _toast('Booking created.');
      Navigator.pop(context); // back
      Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreen(taskId: taskId)));
      Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationScreen(channelId: channelId)));
    } catch (e) {
      _toast('Could not create booking: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Helpers ---

  String _channelId(String a, String b) => a.compareTo(b) < 0 ? '${a}_$b' : '${b}_$a';

  Future<void> _ensureChat(String channelId, String a, String b, String taskId) async {
    final ref = FirebaseFirestore.instance.collection('chats').doc(channelId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'participants': [a, b],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'taskId': taskId,
      }, SetOptions(merge: true));
    } else if (!(snap.data()?['taskId'] is String)) {
      await ref.set({'taskId': taskId}, SetOptions(merge: true));
    }
  }

  Future<void> _postBookingMessage(String channelId, String taskId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final msgRef = FirebaseFirestore.instance.collection('chats').doc(channelId).collection('messages').doc();
    await msgRef.set({
      'type': 'text',
      'text': 'Booking request created · Task #$taskId',
      'senderId': me.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await FirebaseFirestore.instance.collection('chats').doc(channelId).set({
      'lastMessage': 'Booking request created',
      'lastMessageTimestamp': FieldValue.serverTimestamp(),
      'lastMessageSenderId': me.uid,
    }, SetOptions(merge: true));
  }

  Future<void> _tryNotify(String helperId, String taskId) async {
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('notifyBookingRequest');
      await fn.call(<String, dynamic>{
        'helperId': helperId,
        'taskId': taskId,
      });
    } catch (_) {
      // best-effort only
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : null));
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPhysical = _type == 'physical';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book a service'),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primary.withOpacity(0.12),
                  foregroundColor: cs.primary,
                  child: const Icon(Icons.handshake_outlined),
                ),
                title: const Text('You’re booking this helper'),
                subtitle: Text('Helper ID: ${widget.helperId.substring(0, 6)}…'),
              ),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g., Deep house cleaning'),
              validator: (v) => (v == null || v.trim().length < 4) ? 'Please enter at least 4 characters' : null,
            ),
            const SizedBox(height: 12),

            // Type
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'physical', label: Text('Physical')),
                ButtonSegment(value: 'online', label: Text('Online')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),

            // Date & time
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dateCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Date'),
                    onTap: _pickDate,
                    validator: (v) => (v == null || v.isEmpty) ? 'Pick a date' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _startCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Start time'),
                    onTap: () => _pickTime(_startCtrl),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'End time'),
                    onTap: () => _pickTime(_endCtrl),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Price
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Budget (LKR)', hintText: 'e.g., 3500'),
              validator: (v) {
                final n = num.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Address (physical)
            if (isPhysical)
              TextFormField(
                controller: _addressCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Address',
                  hintText: 'Pick a location',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.map_outlined),
                    onPressed: _pickLocation,
                  ),
                ),
                validator: (v) => (isPhysical && (v == null || v.trim().isEmpty)) ? 'Pick an address' : null,
              ),

            if (isPhysical) const SizedBox(height: 12),

            // Notes
            TextFormField(
              controller: _descCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Describe the scope, access details, parking, etc.',
              ),
            ),
          ],
        ),
      ),

      // Submit bar
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _createBooking,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.event_available),
                  label: const Text('Create booking'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtTime(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final mm = t.minute.toString().padLeft(2, '0');
  final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$mm $ampm';
}

String _2(int n) => n.toString().padLeft(2, '0');


// lib/screens/task_details_screen.dart
//
// Task Details — supports being launched with just taskId (loads from Firestore)
// OR with both (taskId + task map). Keeps the features: map, payments, offer actions.
// Uses EligibilityService v2.1 for gating.
// ----------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:servana/services/eligibility_service.dart' as elig;

class TaskDetailsScreen extends StatefulWidget {
  const TaskDetailsScreen({super.key, required this.taskId, this.task});
  final String taskId;
  final Map<String, dynamic>? task;

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  Position? _myPos;
  double? _km;
  int? _walkMin;
  int? _driveMin;

  @override
  void initState() {
    super.initState();
    _loadMyPosition();
  }

  Future<void> _loadMyPosition() async {
    try {
      final svcEnabled = await Geolocator.isLocationServiceEnabled();
      if (!svcEnabled) return;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _myPos = pos);
    } catch (_) {}
  }

  void _computeDistances(Map<String, dynamic> t) {
    final lat = (t['lat'] ?? t['latitude'])?.toDouble();
    final lng = (t['lng'] ?? t['longitude'])?.toDouble();
    if (_myPos == null || lat == null || lng == null) return;
    final d = Geolocator.distanceBetween(_myPos!.latitude, _myPos!.longitude, lat, lng);
    final km = d / 1000.0;
    final walkMin = (km / 5 * 60).round();
    final driveMin = (km / 30 * 60).round();
    setState(() { _km = km; _walkMin = walkMin; _driveMin = driveMin; });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.task != null) {
      return _TaskDetailsScaffold(taskId: widget.taskId, task: widget.task!, myPos: _myPos, km: _km, walkMin: _walkMin, driveMin: _driveMin, onNeedDistance: _computeDistances);
    }
    // Load from Firestore if not provided
    final ref = FirebaseFirestore.instance.collection('tasks').doc(widget.taskId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('Task not found')));
        }
        final t = snap.data!.data()!;
        return _TaskDetailsScaffold(taskId: widget.taskId, task: t, myPos: _myPos, km: _km, walkMin: _walkMin, driveMin: _driveMin, onNeedDistance: _computeDistances);
      },
    );
  }
}

class _TaskDetailsScaffold extends StatelessWidget {
  const _TaskDetailsScaffold({
    required this.taskId,
    required this.task,
    required this.myPos,
    required this.km,
    required this.walkMin,
    required this.driveMin,
    required this.onNeedDistance,
  });

  final String taskId;
  final Map<String, dynamic> task;
  final Position? myPos;
  final double? km;
  final int? walkMin;
  final int? driveMin;
  final void Function(Map<String, dynamic>) onNeedDistance;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final type = (t['type'] ?? (t['isPhysical'] == true ? 'physical' : 'online')).toString().toLowerCase();
    final isPhysical = type == 'physical';
    final category = (t['mainCategory'] ?? t['category'] ?? t['categoryId'] ?? '').toString();
    final price = t['price'] ?? t['amount'] ?? t['budget'] ?? t['budgetMax'] ?? t['budgetMin'];
    final createdAt = _asDate(t['createdAt']) ?? _asDate(t['postedAt']);
    final scheduledAt = _asDate(t['scheduledAt']);
    final payIds = _asStringList(t['paymentMethods']);
    final payOther = (t['paymentOtherNote'] ?? '').toString();
    final hasGeo = t['lat'] != null && t['lng'] != null;

    // Compute distances the first time we render
    if (hasGeo && (km == null || walkMin == null || driveMin == null)) {
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      onNeedDistance(t);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Task details')),
      body: FutureBuilder<elig.CategoryEligibility>(
        future: elig.EligibilityService().checkHelperEligibilityForTask(task),
        builder: (context, snap) {
          final gate = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text((t['title'] ?? '').toString(), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: -6,
                children: [
                  if (isPhysical) const Chip(label: Text('Physical'), visualDensity: VisualDensity.compact),
                  if (!isPhysical) const Chip(label: Text('Online'), visualDensity: VisualDensity.compact),
                  if (category.isNotEmpty) Chip(label: Text(_pretty(category)), visualDensity: VisualDensity.compact),
                  if (price != null) Chip(label: Text(_formatLkr(price)), visualDensity: VisualDensity.compact),
                  if (createdAt != null) Chip(label: Text('Posted ${_timeAgo(createdAt)}'), visualDensity: VisualDensity.compact),
                  if (scheduledAt != null) Chip(label: Text('Starts ${scheduledAt.toLocal()}'), visualDensity: VisualDensity.compact),
                ],
              ),

              if (payIds.isNotEmpty || payOther.isNotEmpty) ...[
                const SizedBox(height: 16),
                PaymentMethodsRow(methodIds: payIds, otherNote: payOther),
              ],

              if (isPhysical && hasGeo) ...[
                const SizedBox(height: 20),
                _PhysicalMapBlock(
                  taskLatLng: LatLng((t['lat'] ?? t['latitude']).toDouble(), (t['lng'] ?? t['longitude']).toDouble()),
                  myPosition: myPos,
                  km: km,
                  walkMins: walkMin,
                  driveMins: driveMin,
                ),
              ],

              const SizedBox(height: 20),
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text((t['description'] ?? '').toString()),

              if (gate != null && !gate.isAllowed) ...[
                _UnlockBanner(
                  categoryId: gate.categoryId,
                  status: gate.status,
                  isBasicDocsReason: gate.reason == 'basic_docs',
                  onVerify: () {
                    if (gate.reason == 'basic_docs') {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open Basic Documents verification.')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open category verification for ${_pretty(gate.categoryId)}.')));
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],

              _OfferActions(
                enabled: gate?.isAllowed ?? false,
                taskId: taskId,
                task: task,
              ),

              const SizedBox(height: 12),
              _MyOfferSection(taskId: taskId, helperId: FirebaseAuth.instance.currentUser!.uid),
            ],
          );
        },
      ),
    );
  }
}

// ---------- Map block --------------------------------------------------------

class _PhysicalMapBlock extends StatelessWidget {
  const _PhysicalMapBlock({
    required this.taskLatLng,
    required this.myPosition,
    required this.km,
    required this.walkMins,
    required this.driveMins,
  });

  final LatLng taskLatLng;
  final Position? myPosition;
  final double? km;
  final int? walkMins;
  final int? driveMins;

  @override
  Widget build(BuildContext context) {
    final hasGeo = taskLatLng.latitude != 0 && taskLatLng.longitude != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Location & distance', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (hasGeo)
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(target: taskLatLng, zoom: 13),
                markers: {
                  Marker(markerId: const MarkerId('task'), position: taskLatLng),
                },
                myLocationEnabled: myPosition != null,
                zoomControlsEnabled: false,
                onMapCreated: (_) {},
              ),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (km != null) Chip(label: Text('${km!.toStringAsFixed(km! < 10 ? 2 : 1)} km away'), visualDensity: VisualDensity.compact),
            if (walkMins != null) Chip(label: Text('~${walkMins} min walk'), visualDensity: VisualDensity.compact),
            if (driveMins != null) Chip(label: Text('~${driveMins} min drive'), visualDensity: VisualDensity.compact),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${taskLatLng.latitude},${taskLatLng.longitude}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.near_me_outlined),
            label: const Text('Open in Google Maps'),
          ),
        ),
      ],
    );
  }
}

// ---------- Payment methods row ---------------------------------------------

class PaymentMethodsRow extends StatelessWidget {
  const PaymentMethodsRow({super.key, required this.methodIds, this.otherNote});

  final List<String> methodIds;
  final String? otherNote;

  @override
  Widget build(BuildContext context) {
    String labelFor(String id) => const {
      'bank_transfer': 'Bank transfer',
      'servcoins': 'Coins',
      'card': 'Card',
      'cash': 'Cash',
      'other': 'Other',
    }[id] ?? id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment methods', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: -6,
          children: [
            for (final id in methodIds) Chip(label: Text(labelFor(id)), visualDensity: VisualDensity.compact),
            if (methodIds.contains('other') && (otherNote ?? '').isNotEmpty)
              Chip(label: Text(otherNote!), visualDensity: VisualDensity.compact),
          ],
        ),
      ],
    );
  }
}

// ---------- Unlock banner ----------------------------------------------------

class _UnlockBanner extends StatelessWidget {
  const _UnlockBanner({
    required this.categoryId,
    required this.status,
    required this.onVerify,
    required this.isBasicDocsReason,
  });
  final String categoryId;
  final String status;
  final bool isBasicDocsReason;
  final VoidCallback onVerify;
  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (status) {
      case 'processing':
        bg = Colors.orange.shade50; fg = Colors.orange.shade900; break;
      case 'pending':
        bg = Colors.yellow.shade50; fg = Colors.yellow.shade900; break;
      case 'rejected':
        bg = Colors.red.shade50; fg = Colors.red.shade900; break;
      default:
        bg = Colors.blue.shade50; fg = Colors.blue.shade900;
    }

    final text = isBasicDocsReason
        ? 'Verify basic documents to make offers on physical tasks.'
        : 'Verify for ${_pretty(categoryId)} to make offers.';

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user_outlined),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
          TextButton.icon(
            onPressed: onVerify,
            icon: Icon(Icons.verified_outlined, color: fg),
            label: Text('Verify now', style: TextStyle(color: fg)),
          )
        ],
      ),
    );
  }
}

// ---------- Offer actions ----------------------------------------------------

class _OfferActions extends StatefulWidget {
  const _OfferActions({
    required this.enabled,
    required this.taskId,
    required this.task,
  });
  final bool enabled;
  final String taskId;
  final Map<String, dynamic> task;

  @override
  State<_OfferActions> createState() => _OfferActionsState();
}

class _OfferActionsState extends State<_OfferActions> {
  bool _busy = false;
  String? _err;
  Map<String, dynamic>? _my;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _offersCol =>
      FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).collection('offers');

  @override
  void initState() {
    super.initState();
    _loadMy();
  }

  Future<void> _loadMy() async {
    setState(() => _busy = true);
    try {
      final q = await _offersCol
          .where('helperId', isEqualTo: _uid)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();
      _my = q.docs.isEmpty ? null : q.docs.first.data();
    } catch (e) {
      _err = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSheet() async {
    final data = _my;
    final priceCtrl = TextEditingController(text: (data?['price'] ?? data?['amount'] ?? '').toString());
    final noteCtrl = TextEditingController(text: (data?['message'] ?? data?['note'] ?? '').toString());

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data == null ? 'Make an offer' : 'Edit your offer', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (LKR)')),
              const SizedBox(height: 8),
              TextField(controller: noteCtrl, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Message to poster (optional)')),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final amount = double.tryParse(priceCtrl.text.trim()) ?? 0;
                      final note = noteCtrl.text.trim();
                      Navigator.pop(ctx);
                      await _saveOffer(amount, note);
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(data == null ? 'Submit offer' : 'Save changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveOffer(double amount, String note) async {
    setState(() => _busy = true);
    try {
      final now = FieldValue.serverTimestamp();
      final q = await _offersCol
          .where('helperId', isEqualTo: _uid)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();
      if (q.docs.isEmpty) {
        await _offersCol.add({
          'helperId': _uid,
          'price': amount,
          'amount': amount,
          'message': note,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        });
      } else {
        await q.docs.first.reference.update({
          'price': amount,
          'amount': amount,
          'message': note,
          'status': 'pending',
          'updatedAt': now,
        });
      }
      await _loadMy();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      final q = await _offersCol
          .where('helperId', isEqualTo: _uid)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        await q.docs.first.reference.update({'status': 'withdrawn', 'updatedAt': FieldValue.serverTimestamp()});
      }
      await _loadMy();
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dis = !widget.enabled || _busy;
    final status = (_my?['status'] ?? 'none').toString();
    final counter = _my?['counterPrice'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake_outlined, size: 18),
                const SizedBox(width: 8),
                Text('Offers', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 8),
            if (!widget.enabled)
              Text('You must verify before you can make an offer.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: dis ? null : _openSheet,
                  icon: const Icon(Icons.local_offer_outlined),
                  label: Text(_my == null ? 'Make offer' : 'Edit offer'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: dis || _my == null ? null : _withdraw,
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Withdraw'),
                ),
                const SizedBox(width: 8),
                if (counter != null)
                  OutlinedButton.icon(
                    onPressed: dis ? null : () => _saveOffer((counter as num).toDouble(), (_my?['message'] ?? '').toString()),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text('Accept counter ${_formatLkr(counter)}'),
                  ),
              ],
            ),
            if (_my != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Your offer: ${_formatLkr(_my?['price'] ?? _my?['amount'])}'),
                  const SizedBox(width: 12),
                  Text('Status: $status'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------- My offers stream -----------------------------------------------

class _MyOfferSection extends StatelessWidget {
  const _MyOfferSection({required this.taskId, required this.helperId});
  final String taskId;
  final String helperId;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('tasks')
        .doc(taskId)
        .collection('offers')
        .where('helperId', isEqualTo: helperId)
        .orderBy('updatedAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();
        final d = docs.first.data();
        final status = (d['status'] ?? 'pending').toString();
        return ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text('Latest offer: ${_formatLkr(d['price'] ?? d['amount'])}'),
          subtitle: Text('Status: $status  — updated ${(d['updatedAt'] is Timestamp) ? _timeAgo((d['updatedAt'] as Timestamp).toDate()) : ''}'),
        );
      },
    );
  }
}

// ---------- Helpers ----------------------------------------------------------

String _pretty(String s) => s.replaceAll('_', ' ').splitMapJoin(
      RegExp(r'\b\w'),
      onMatch: (m) => m.group(0)!.toUpperCase(),
      onNonMatch: (n) => n,
    );

String _formatLkr(dynamic v) {
  if (v == null) return '—';
  final n = double.tryParse(v.toString()) ?? 0;
  return 'LKR ${n.toStringAsFixed(n % 1 == 0 ? 0 : 2)}';
}

DateTime? _asDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return null;
}

String _timeAgo(DateTime dt) {
  final s = DateTime.now().difference(dt);
  if (s.inMinutes < 1) return 'just now';
  if (s.inMinutes < 60) return '${s.inMinutes}m ago';
  if (s.inHours < 24) return '${s.inHours}h ago';
  return '${s.inDays}d ago';
}

List<String> _asStringList(dynamic v) {
  if (v is Iterable) return v.map((e) => e.toString()).toList();
  if (v is String && v.isNotEmpty) return [v];
  return const [];
}

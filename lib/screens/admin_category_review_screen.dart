// lib/screens/admin_category_review_screen.dart
//
// Admin Category Review (Polished)
// --------------------------------
// • Tabs: Pending • Needs info • Verified • Rejected
// • Pending tab treats both 'submitted' and 'pending' as pending (whereIn query)
// • Mode filter: All • Physical • Online • Basic (client-side filter using categories collection)
// • Search by UID or Category label
// • Per-card actions: Verify • Needs info (note required) • Reject (note required)
// • Bulk actions across selected items with batched writes (safe up to 400 per batch)
//
// Deps: cloud_firestore, firebase_auth, flutter/material, url_launcher
//
// Notes on statuses:
// - We use 'verified' for the approved state to match your Cloud Function.
// - Pending uses either 'submitted' or 'pending'.
//
// Documents:
//   category_proofs/{uid}_{categoryId} => { uid, categoryId, status, documents[], notes?, submittedAt?, verifiedAt?, updatedAt? }
//   categories/{categoryId} => { label, mode: 'online'|'physical' }
//
// This screen requires the current user to be admin; otherwise shows a guard.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminCategoryReviewScreen extends StatefulWidget {
  const AdminCategoryReviewScreen({super.key});

  @override
  State<AdminCategoryReviewScreen> createState() => _AdminCategoryReviewScreenState();
}

class _AdminCategoryReviewScreenState extends State<AdminCategoryReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _modeFilter = 'all'; // all | physical | online | basic
  final Set<String> _selected = <String>{}; // docIds

  Map<String, Map<String, dynamic>> _categories = {}; // id -> data (label, mode)

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final qs = await FirebaseFirestore.instance.collection('categories').get();
      final map = <String, Map<String, dynamic>>{};
      for (final d in qs.docs) {
        final data = d.data();
        map[d.id] = {
          'label': (data['label'] ?? d.id).toString(),
          'mode': (data['mode'] ?? 'physical').toString().toLowerCase(),
        };
      }
      setState(() => _categories = map);
    } catch (_) {
      // ignore; defaults will apply
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _isAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final m = snap.data() ?? {};
    final roles = (m['roles'] is Map) ? Map<String, dynamic>.from(m['roles']) : const <String, dynamic>{};
    if (m['isAdmin'] == true || roles['admin'] == true) return true;
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdTokenResult(true);
      return token.claims?['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data != true) {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin – Category Review')),
            body: Center(
              child: Text('Admin access required.', style: TextStyle(color: cs.error)),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Category Proofs Review'),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Pending'),
                Tab(text: 'Needs info'),
                Tab(text: 'Verified'),
                Tab(text: 'Rejected'),
              ],
            ),
          ),
          body: Column(
            children: [
              // Search + Mode filter + Bulk actions
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by UID or category',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ModeChips(
                      value: _modeFilter,
                      onChanged: (m) => setState(() => _modeFilter = m),
                    ),
                  ],
                ),
              ),
              if (_selected.isNotEmpty)
                _BulkBar(
                  count: _selected.length,
                  onVerify: () => _bulkUpdate('verified'),
                  onNeedsInfo: () => _askNoteThenBulk('needs_more_info'),
                  onReject: () => _askNoteThenBulk('rejected'),
                  onClear: () => setState(() => _selected.clear()),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: [
                    _ProofList(
                      // pending whereIn
                      status: null,
                      whereIn: const ['submitted', 'pending'],
                      modeFilter: _modeFilter,
                      queryText: _query,
                      categories: _categories,
                      selected: _selected,
                      onSelectToggle: _toggleSelect,
                    ),
                    _ProofList(
                      status: 'needs_more_info',
                      modeFilter: _modeFilter,
                      queryText: _query,
                      categories: _categories,
                      selected: _selected,
                      onSelectToggle: _toggleSelect,
                    ),
                    _ProofList(
                      status: 'verified',
                      modeFilter: _modeFilter,
                      queryText: _query,
                      categories: _categories,
                      selected: _selected,
                      onSelectToggle: _toggleSelect,
                    ),
                    _ProofList(
                      status: 'rejected',
                      modeFilter: _modeFilter,
                      queryText: _query,
                      categories: _categories,
                      selected: _selected,
                      onSelectToggle: _toggleSelect,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleSelect(String docId) {
    setState(() {
      if (_selected.contains(docId)) {
        _selected.remove(docId);
      } else {
        _selected.add(docId);
      }
    });
  }

  Future<void> _bulkUpdate(String status, {String? note}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;

    final ids = _selected.toList(growable: false);
    const MAX_PER_BATCH = 400;
    int idx = 0;

    try {
      while (idx < ids.length) {
        final batch = fs.batch();
        for (int i = 0; i < MAX_PER_BATCH && idx < ids.length; i++, idx++) {
          final id = ids[idx];
          final ref = fs.collection('category_proofs').doc(id);
          final payload = <String, dynamic>{
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
            'reviewerId': uid,
          };
          // Verified gets a timestamp
          if (status == 'verified') {
            payload['verifiedAt'] = FieldValue.serverTimestamp();
          }
          if (note != null && note.trim().isNotEmpty) {
            payload['notes'] = note.trim();
          }
          batch.set(ref, payload, SetOptions(merge: true));
        }
        await batch.commit();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated ${ids.length} items → $status')));
      }
      setState(() => _selected.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bulk update failed: $e')));
      }
    }
  }

  Future<void> _askNoteThenBulk(String status) async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _NoteDialog(title: 'Reviewer note (required)'),
    );
    if (note == null) return;
    final n = note.trim();
    if (n.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note is required.')));
      return;
    }
    await _bulkUpdate(status, note: n);
  }
}

class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('All'),
          selected: value == 'all',
          onSelected: (_) => onChanged('all'),
          selectedColor: cs.primary,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: value == 'all' ? cs.onPrimary : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        ChoiceChip(
          label: const Text('Physical'),
          selected: value == 'physical',
          onSelected: (_) => onChanged('physical'),
          selectedColor: cs.primary,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: value == 'physical' ? cs.onPrimary : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        ChoiceChip(
          label: const Text('Online'),
          selected: value == 'online',
          onSelected: (_) => onChanged('online'),
          selectedColor: cs.primary,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: value == 'online' ? cs.onPrimary : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        ChoiceChip(
          label: const Text('Basic'),
          selected: value == 'basic',
          onSelected: (_) => onChanged('basic'),
          selectedColor: cs.primary,
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: value == 'basic' ? cs.onPrimary : null,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.onVerify,
    required this.onNeedsInfo,
    required this.onReject,
    required this.onClear,
  });
  final int count;
  final VoidCallback onVerify;
  final VoidCallback onNeedsInfo;
  final VoidCallback onReject;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('$count selected'),
          const Spacer(),
          OutlinedButton.icon(onPressed: onNeedsInfo, icon: const Icon(Icons.rule_folder_outlined), label: const Text('Needs info')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: onReject, icon: const Icon(Icons.cancel_outlined), label: const Text('Reject')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: onVerify, icon: const Icon(Icons.verified_rounded), label: const Text('Verify')),
          IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded), tooltip: 'Clear selection'),
        ],
      ),
    );
  }
}

class _ProofList extends StatelessWidget {
  const _ProofList({
    this.status,
    this.whereIn,
    required this.modeFilter,
    required this.queryText,
    required this.categories,
    required this.selected,
    required this.onSelectToggle,
  });
  final String? status; // null means use whereIn
  final List<String>? whereIn; // used for pending (submitted | pending)
  final String modeFilter;
  final String queryText;
  final Map<String, Map<String, dynamic>> categories;
  final Set<String> selected;
  final void Function(String docId) onSelectToggle;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q =
    FirebaseFirestore.instance.collection('category_proofs');

    if (status != null) {
      q = q.where('status', isEqualTo: status);
    } else if (whereIn != null && whereIn!.isNotEmpty) {
      q = q.where('status', whereIn: whereIn);
    }

    q = q.orderBy('submittedAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.limit(200).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snap.data!.docs;

        // Client-side mode filter + text filter
        docs = docs.where((d) {
          final m = d.data();
          final uid = (m['uid'] ?? '').toString();
          final cat = (m['categoryId'] ?? '').toString();
          final label = (categories[cat]?['label'] ?? cat).toString();
          final mode = (cat == 'basic')
              ? 'basic'
              : (categories[cat]?['mode'] ?? 'physical').toString();

          if (modeFilter != 'all') {
            if (modeFilter == 'basic' && mode != 'basic') return false;
            if (modeFilter != 'basic' && mode != modeFilter) return false;
          }

          if (queryText.isEmpty) return true;
          return uid.toLowerCase().contains(queryText) ||
              label.toLowerCase().contains(queryText);
        }).toList(growable: false);

        if (docs.isEmpty) {
          return const _Empty(title: 'No items here.');
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = docs[i];
            return _ProofCard(
              doc: doc,
              catLabel: (categories[doc['categoryId']]?['label'] ?? doc['categoryId']).toString(),
              catMode: (doc['categoryId'] == 'basic')
                  ? 'basic'
                  : (categories[doc['categoryId']]?['mode'] ?? 'physical').toString(),
              selected: selected.contains(doc.id),
              onSelectToggle: () => onSelectToggle(doc.id),
            );
          },
        );
      },
    );
  }
}

class _ProofCard extends StatefulWidget {
  const _ProofCard({
    required this.doc,
    required this.catLabel,
    required this.catMode,
    required this.selected,
    required this.onSelectToggle,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String catLabel;
  final String catMode;
  final bool selected;
  final VoidCallback onSelectToggle;

  @override
  State<_ProofCard> createState() => _ProofCardState();
}

class _ProofCardState extends State<_ProofCard> {
  bool _saving = false;

  Future<void> _setStatus(String status) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    try {
      setState(() => _saving = true);
      final payload = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewerId': uid,
      };
      if (status == 'verified') {
        payload['verifiedAt'] = FieldValue.serverTimestamp();
      }
      await fs.collection('category_proofs').doc(widget.doc.id).set(payload, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated ${widget.doc.id} → $status')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _needsInfo() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _NoteDialog(title: 'Reviewer note (required)'),
    );
    if (note == null || note.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note is required.')));
      return;
    }
    await _setStatusWithNote('needs_more_info', note.trim());
  }

  Future<void> _reject() async {
    final note = await showDialog<String>(
      context: context,
      builder: (context) => const _NoteDialog(title: 'Rejection reason (required)'),
    );
    if (note == null || note.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note is required.')));
      return;
    }
    await _setStatusWithNote('rejected', note.trim());
  }

  Future<void> _setStatusWithNote(String status, String note) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    try {
      setState(() => _saving = true);
      await fs.collection('category_proofs').doc(widget.doc.id).set({
        'status': status,
        'notes': note,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewerId': uid,
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Updated ${widget.doc.id} → $status')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = widget.doc.data();
    final uid = (m['uid'] ?? '').toString();
    final cat = (m['categoryId'] ?? '').toString();
    final status = (m['status'] ?? '').toString();
    final docs = (m['documents'] as List?) ?? const <dynamic>[];
    final submittedAt = m['submittedAt'] is Timestamp ? (m['submittedAt'] as Timestamp).toDate() : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.selected ? cs.primaryContainer.withOpacity(.25) : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: selection + title
          Row(
            children: [
              Checkbox(value: widget.selected, onChanged: (_) => widget.onSelectToggle()),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('User: $uid', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Category: ${widget.catLabel}  •  ${widget.catMode.toUpperCase()}',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    if (submittedAt != null)
                      Text('Submitted: ${submittedAt.toLocal()}',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusBg(cs, status),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(status.toUpperCase(), style: TextStyle(color: _statusFg(cs, status), fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Documents quickview
          if (docs.isEmpty)
            Text('No documents uploaded', style: TextStyle(color: cs.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: docs.map((e) {
                final dm = (e as Map).cast<String, dynamic>();
                final type = (dm['type'] ?? '').toString();
                final url = (dm['downloadUrl'] ?? '').toString();
                final name = (dm['fileName'] ?? type).toString();
                return OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(url);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(name, overflow: TextOverflow.ellipsis),
                );
              }).toList().cast<Widget>(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _needsInfo,
                  icon: const Icon(Icons.rule_folder_outlined),
                  label: const Text('Needs info'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _reject,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _setStatus('verified'),
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_rounded),
                  label: const Text('Verify'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusBg(ColorScheme cs, String status) {
    switch (status) {
      case 'verified': return Colors.green.withOpacity(.12);
      case 'rejected': return Colors.red.withOpacity(.12);
      case 'needs_more_info': return Colors.orange.withOpacity(.12);
      default: return cs.surfaceVariant;
    }
  }

  Color _statusFg(ColorScheme cs, String status) {
    switch (status) {
      case 'verified': return Colors.green.shade800;
      case 'rejected': return Colors.red.shade800;
      case 'needs_more_info': return Colors.orange.shade800;
      default: return cs.onSurfaceVariant;
    }
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title});
  final String title;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        maxLines: 3,
        maxLength: 500,
        decoration: const InputDecoration(
          hintText: 'Write a short, clear note for the helper…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Save')),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 44, color: cs.outline),
            const SizedBox(height: 10),
            Text(title),
          ],
        ),
      ),
    );
  }
}

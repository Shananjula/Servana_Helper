// lib/screens/conversation_screen.dart
//
// ConversationScreen (Phase 1 — richer chat)
// ------------------------------------------
// Works with either:
//   ConversationScreen(channelId: '<chat|pair id>')
// or
//   ConversationScreen(otherUserId: '<uid>', otherUserName: 'Name')
//
// Adds in Phase 1:
//  • Image sending (gallery) → Firebase Storage
//  • Typing indicators (typing.{uid} = true + typingAt.{uid})
//  • Read receipts (readBy.{uid} = true best-effort on visible messages)
//  • Long-press on a message: Copy (text), Star/Unstar, Delete for me
//
// Collections (tolerant):
//   chats/{id} or pairs/{id} {
//     participants: [uidA, uidB], lastMessage, updatedAt, typing?:{uid:true}, typingAt?:{uid:ts}
//   }
//   .../messages/{mid} {
//     type: 'text'|'image', text?, imageUrl?,
//     senderId, timestamp, readBy?:{uid:true}, starredBy?:{uid:true}, deletedFor?:{uid:true}
//   }

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:servana/services/quick_replies_service.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    this.channelId,
    this.otherUserId,
    this.otherUserName,
  });

  final String? channelId;
  final String? otherUserId;
  final String? otherUserName;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  String? _meId;
  String? _chatId;
  String? _otherId;
  String? _otherName;
  String _coll = 'chats'; // 'chats' or 'pairs'
  bool _bootstrapping = true;

  // typing indicator
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _msgCtrl.addListener(_onComposerChanged);
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_onComposerChanged);
    _msgCtrl.dispose();
    _typingOffDebounced();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final me = FirebaseAuth.instance.currentUser;
    _meId = me?.uid;
    if (_meId == null) {
      setState(() => _bootstrapping = false);
      return;
    }

    String? chatId = widget.channelId?.trim().isEmpty == true ? null : widget.channelId?.trim();
    String? otherId = widget.otherUserId?.trim().isEmpty == true ? null : widget.otherUserId?.trim();

    if (chatId == null && otherId != null) {
      chatId = _pairKey(_meId!, otherId);
    }

    String coll = 'chats';
    if (chatId != null) {
      final chatsDoc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
      if (!chatsDoc.exists) {
        final pairsDoc = await FirebaseFirestore.instance.collection('pairs').doc(chatId).get();
        coll = pairsDoc.exists ? 'pairs' : 'chats';
      }
    }

    // Create shell in /chats if needed
    if (coll == 'chats' && chatId != null) {
      final ref = FirebaseFirestore.instance.collection('chats').doc(chatId);
      final snap = await ref.get();
      if (!snap.exists) {
        otherId ??= _otherFromPairKey(chatId, _meId!);
        await ref.set({
          'participants': otherId == null ? [_meId] : [_meId, otherId]..sort(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final m = snap.data() ?? {};
        final parts = (m['participants'] is List) ? List<String>.from(m['participants']) : const <String>[];
        if (parts.isNotEmpty) otherId ??= parts.firstWhere((p) => p != _meId, orElse: () => parts.first);
      }
    } else if (coll == 'pairs' && chatId != null) {
      final ps = await FirebaseFirestore.instance.collection('pairs').doc(chatId).get();
      final m = ps.data() ?? {};
      final mem = (m['members'] is List) ? List<String>.from(m['members']) : const <String>[];
      if (mem.isNotEmpty) otherId ??= mem.firstWhere((p) => p != _meId, orElse: () => mem.first);
    }

    String? otherName = widget.otherUserName;
    if ((otherName == null || otherName.trim().isEmpty) && (otherId != null)) {
      try {
        final u = await FirebaseFirestore.instance.collection('users').doc(otherId).get();
        final d = u.data() ?? {};
        final n = (d['displayName'] ?? '').toString().trim();
        if (n.isNotEmpty) otherName = n;
      } catch (_) {}
    }

    setState(() {
      _chatId = chatId;
      _otherId = otherId;
      _otherName = otherName?.isNotEmpty == true ? otherName : null;
      _coll = coll;
      _bootstrapping = false;
    });
  }

  String _pairKey(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  String? _otherFromPairKey(String pair, String me) {
    if (!pair.contains('_')) return null;
    final parts = pair.split('_')..sort();
    if (parts.length != 2) return null;
    return parts.first == me ? parts[1] : parts.first;
  }

  // ---------- typing ----------

  void _onComposerChanged() {
    _setTyping(true);
    _typingOffDebounced();
  }

  void _typingOffDebounced() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () => _setTyping(false));
  }

  Future<void> _setTyping(bool typing) async {
    if (_meId == null || _chatId == null) return;
    try {
      await FirebaseFirestore.instance.collection(_coll).doc(_chatId!).set({
        'typing': {_meId!: typing},
        'typingAt': {_meId!: FieldValue.serverTimestamp()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ---------- send ----------

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _meId == null || _chatId == null) return;

    final db = FirebaseFirestore.instance;
    final root = db.collection(_coll).doc(_chatId!);
    final msgs = root.collection('messages');

    try {
      await msgs.add({
        'type': 'text',
        'senderId': _meId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await root.set({
        'lastMessage': text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _msgCtrl.clear();
      _setTyping(false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    }
  }

  Future<void> _sendImage() async {
    if (_meId == null || _chatId == null) return;
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
      if (x == null) return;

      final ref = FirebaseStorage.instance
          .ref('chat_uploads/${_chatId!}/${DateTime.now().millisecondsSinceEpoch}_${x.name}');
      await ref.putFile(File(x.path));
      final url = await ref.getDownloadURL();

      final db = FirebaseFirestore.instance;
      final root = db.collection(_coll).doc(_chatId!);
      final msgs = root.collection('messages');

      await msgs.add({
        'type': 'image',
        'senderId': _meId,
        'imageUrl': url,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await root.set({
        'lastMessage': '📷 Photo',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image failed: $e')));
    }
  }

  // ---------- read receipts ----------

  Future<void> _markRead(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_meId == null) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      var count = 0;
      for (final d in docs) {
        final m = d.data();
        if ((m['senderId'] ?? '') == _meId) continue;
        final readMap = (m['readBy'] is Map) ? Map<String, dynamic>.from(m['readBy']) : <String, dynamic>{};
        if (readMap[_meId] == true) continue;
        batch.set(d.reference, {'readBy.${_meId!}': true}, SetOptions(merge: true));
        count++;
        if (count >= 30) break; // safety cap
      }
      if (count > 0) await batch.commit();
    } catch (_) {}
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _otherName ?? (_otherId != null ? 'Chat' : 'Conversation');

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _otherId == null ? null : FirebaseFirestore.instance.collection('users').doc(_otherId).get(),
          builder: (context, usnap) {
            final verified = (usnap.data?.data()?['verificationStatus'] ?? '').toString().toLowerCase().contains('verified');
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
                if (verified) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.verified_rounded, size: 18, color: Colors.green.shade700),
                ],
              ],
            );
          },
        ),
        centerTitle: false,
      ),
      backgroundColor: cs.background,
      body: _bootstrapping
          ? const Center(child: CircularProgressIndicator())
          : (_chatId == null && _otherId == null)
          ? const Center(child: Text('Missing chat identifiers.'))
          : Column(
        children: [
          // typing banner
          _TypingBanner(coll: _coll, chatId: _chatId!, meId: _meId!),

          Expanded(
              child: _MessagesList(
                coll: _coll,
                chatId: _chatId!,
                meId: _meId!,
                onBatchShown: _markRead,
              )),

          _QuickRepliesBar(
            onPick: (text) {
              final current = _msgCtrl.text.trim();
              _msgCtrl.text = current.isEmpty ? text : '$current $text';
              _msgCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _msgCtrl.text.length));
            },
            onManage: () => _openManageReplies(context),
          ),

          _Composer(
            enabled: _meId != null && _chatId != null,
            controller: _msgCtrl,
            onSend: _sendText,
            onImage: _sendImage,
          ),
        ],
      ),
    );
  }

  Future<void> _openManageReplies(BuildContext context) async {
    final current = await QuickRepliesService.streamReplies().first;
    final ctrl = TextEditingController(text: current.join('\n'));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quick replies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'One reply per line (max 6).',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type one quick reply per line…',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Save'),
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      final lines = ctrl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      await QuickRepliesService.saveReplies(lines);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quick replies saved')));
      }
    }
  }
}

class _TypingBanner extends StatelessWidget {
  const _TypingBanner({required this.coll, required this.chatId, required this.meId});
  final String coll;
  final String chatId;
  final String meId;

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection(coll).doc(chatId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final m = snap.data?.data() ?? {};
        final typing = (m['typing'] is Map) ? Map<String, dynamic>.from(m['typing']) : const <String, dynamic>{};
        final othersTyping = typing.entries.any((e) => e.key != meId && e.value == true);
        if (!othersTyping) return const SizedBox(height: 0);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text('Typing…', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
      },
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({
    required this.coll,
    required this.chatId,
    required this.meId,
    required this.onBatchShown,
  });

  final String coll;
  final String chatId;
  final String meId;
  final Future<void> Function(Iterable<QueryDocumentSnapshot<Map<String, dynamic>>>) onBatchShown;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection(coll)
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.limit(200).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;

        // mark read best-effort
        WidgetsBinding.instance.addPostFrameCallback((_) => onBatchShown(docs));

        if (docs.isEmpty) {
          return const Center(child: Text('Say hi 👋'));
        }

        return ListView.builder(
          controller: ScrollController(),
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final m = docs[i].data();
            final from = (m['senderId'] ?? '').toString();
            final type = (m['type'] ?? 'text').toString();
            final text = (m['text'] ?? '').toString();
            final imageUrl = (m['imageUrl'] ?? '').toString();
            final mine = from == meId;

            // Respect "delete for me"
            final deletedFor = (m['deletedFor'] is Map) ? (m['deletedFor'][meId] == true) : false;
            if (deletedFor) return const SizedBox.shrink();

            final bubble = type == 'image'
                ? _ImageBubble(url: imageUrl, mine: mine)
                : _TextBubble(text: text, mine: mine);

            return GestureDetector(
              onLongPress: () => _onLongPress(context, docs[i], m),
              child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: bubble,
              ),
            );
          },
        );
      },
    );
  }

  void _onLongPress(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc, Map<String, dynamic> m) async {
    final uid = meId;
    final starred = (m['starredBy'] is Map) ? (m['starredBy'][uid] == true) : false;
    final type = (m['type'] ?? 'text').toString();
    final text = (m['text'] ?? '').toString();

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (type == 'text' && text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy text'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            ListTile(
              leading: Icon(starred ? Icons.star : Icons.star_border),
              title: Text(starred ? 'Unstar' : 'Star'),
              onTap: () => Navigator.pop(context, 'star'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete for me'),
              onTap: () => Navigator.pop(context, 'delete_me'),
            ),
          ],
        ),
      ),
    );

    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
        }
        break;
      case 'star':
        try {
          await doc.reference.set({'starredBy.$uid': starred ? FieldValue.delete() : true}, SetOptions(merge: true));
        } catch (_) {}
        break;
      case 'delete_me':
        try {
          await doc.reference.set({'deletedFor.$uid': true}, SetOptions(merge: true));
        } catch (_) {}
        break;
      default:
        break;
    }
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.text, required this.mine});
  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? cs.primaryContainer : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Text(text),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.url, required this.mine});
  final String url;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: mine ? cs.primaryContainer : cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, width: 220, fit: BoxFit.cover),
      ),
    );
  }
}

class _QuickRepliesBar extends StatelessWidget {
  const _QuickRepliesBar({required this.onPick, required this.onManage});
  final void Function(String text) onPick;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<String>>(
      stream: QuickRepliesService.streamReplies(),
      builder: (context, snap) {
        final replies = (snap.data ?? QuickRepliesService.defaultReplies).take(6).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: replies
                        .map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onPressed: () => onPick(t),
                        backgroundColor: cs.surface,
                        side: BorderSide(color: cs.outline.withOpacity(0.12)),
                      ),
                    ))
                        .toList(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Manage quick replies',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: onManage,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.enabled,
    required this.controller,
    required this.onSend,
    required this.onImage,
  });

  final bool enabled;
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onImage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withOpacity(0.12))),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Add photo',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: enabled ? onImage : null,
          ),
          Expanded(
            child: TextField(
              enabled: enabled,
              controller: controller,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Type a message…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

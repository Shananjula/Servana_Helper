// lib/screens/community_feed_screen.dart
//
// Community Feed (Helpers & Posters)
// • Create post (text + optional images)
// • Infinite scroll feed (newest first)
// • Like / Unlike with optimistic UI
// • Delete own post (confirm)
// • Basic tags (optional)
// • View comments → (navigate to your comments screen if you have one)
//
// Firestore collections used:
//  posts/{postId} (see CommunityPost model for fields)
//  posts/{postId}/comments/* (not implemented here)
//
// Notes:
// • Safe to drop into existing project; no extra packages required.
// • Image picking uses ImagePicker in your other screens; to keep this screen
//   lightweight and dependency-free, we only handle text + URL pasting here.
// • If you want in-app gallery uploads, tell me and I’ll add image_picker + Storage flow.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:servana/models/community_post_model.dart';
import 'package:servana/widgets/empty_state_widget.dart';

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  final _postCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  bool _posting = false;
  final List<String> _imageUrls = [];

  @override
  void dispose() {
    _postCtrl.dispose();
    _imageUrlCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _addImageUrl() async {
    final url = _imageUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _imageUrls.add(url);
      _imageUrlCtrl.clear();
    });
  }

  Future<void> _removeImageUrl(int i) async {
    setState(() => _imageUrls.removeAt(i));
  }

  Future<void> _createPost() async {
    final text = _postCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write something first.')));
      return;
    }
    if (_uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in.')));
      return;
    }

    setState(() => _posting = true);
    try {
      final tags = _tagCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final ref = FirebaseFirestore.instance.collection('posts').doc();
      await ref.set({
        'authorId': _uid,
        'text': text,
        if (_imageUrls.isNotEmpty) 'imageUrls': _imageUrls,
        if (tags.isNotEmpty) 'tags': tags,
        'likeCount': 0,
        'commentCount': 0,
        'likedBy': {},
        'isEdited': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _postCtrl.clear();
        _imageUrls.clear();
        _tagCtrl.clear();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Posted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not post: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggleLike(CommunityPost p) async {
    if (_uid.isEmpty) return;
    final ref = FirebaseFirestore.instance.collection('posts').doc(p.id);
    final currently = p.isLikedBy(_uid);

    // Optimistic: local snack
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(currently ? 'Removed like' : 'Liked'),
      duration: const Duration(milliseconds: 900),
    ));

    try {
      await FirebaseFirestore.instance.runTransaction((trx) async {
        final snap = await trx.get(ref);
        final m = snap.data() as Map<String, dynamic>? ?? {};
        final lc = (m['likeCount'] is num) ? (m['likeCount'] as num).toInt() : 0;
        final likedBy = (m['likedBy'] is Map) ? Map<String, dynamic>.from(m['likedBy']) : <String, dynamic>{};

        if (currently) {
          likedBy[_uid] = FieldValue.delete();
        } else {
          likedBy[_uid] = true;
        }

        trx.set(ref, {
          'likedBy': likedBy,
          'likeCount': (lc + (currently ? -1 : 1)).clamp(0, 1 << 31),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _deletePost(CommunityPost p) async {
    if (p.authorId != _uid) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('posts').doc(p.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Composer
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _postCtrl,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: "Share an update, ask a question…",
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Add image via URL (keep lightweight); proper uploads can be added later.
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _imageUrlCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Paste image URL (optional)',
                            prefixIcon: Icon(Icons.link_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _addImageUrl,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                  if (_imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(_imageUrls[i], height: 88, width: 120, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 4,
                              top: 4,
                              child: IconButton.filledTonal(
                                icon: const Icon(Icons.close),
                                onPressed: () => _removeImageUrl(i),
                              ),
                            ),
                          ],
                        ),
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: _imageUrls.length,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tagCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Tags (comma-separated, optional)',
                      prefixIcon: Icon(Icons.sell_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _posting ? null : _createPost,
                        icon: _posting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded),
                        label: const Text('Post'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Feed
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const EmptyStateWidget(
                    icon: Icons.campaign_outlined,
                    title: 'No posts yet',
                    message: 'Start a conversation with the community.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final post = CommunityPost.fromDoc(docs[i]);
                    return _PostCard(
                      post: post,
                      onLike: () => _toggleLike(post),
                      onDelete: post.authorId == _uid ? () => _deletePost(post) : null,
                      onOpenComments: () {
                        // TODO: push to your comments screen: PostCommentsScreen(postId: post.id)
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Post tile ----------------

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onLike,
    required this.onOpenComments,
    this.onDelete,
  });

  final CommunityPost post;
  final VoidCallback onLike;
  final VoidCallback onOpenComments;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author row
            Row(
              children: [
                CircleAvatar(
                  child: Text(post.authorName?.isNotEmpty == true
                      ? post.authorName![0].toUpperCase()
                      : (post.authorId.isNotEmpty ? post.authorId[0].toUpperCase() : '?')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    post.authorName ?? 'User ${post.authorId.substring(0, 6)}…',
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onDelete != null)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Text
            if (post.text.isNotEmpty)
              Text(post.text),

            // Images
            if (post.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: post.imageUrls.length,
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(post.imageUrls[i], height: 120, width: 160, fit: BoxFit.cover),
                  ),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                ),
              ),
            ],

            // Tags
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: -6,
                children: post.tags.map((t) => Chip(label: Text('#$t'), visualDensity: VisualDensity.compact)).toList(),
              ),
            ],

            const SizedBox(height: 10),

            // Actions
            Row(
              children: [
                TextButton.icon(
                  onPressed: onLike,
                  icon: Icon(Icons.thumb_up_alt_outlined, color: post.isLikedBy(FirebaseAuth.instance.currentUser?.uid ?? '') ? cs.primary : null),
                  label: Text('${post.likeCount}'),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: onOpenComments,
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('${post.commentCount}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

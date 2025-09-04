// lib/models/community_post_model.dart
//
// CommunityPost model (friendly with Firestore; merge-safe)
// • Supports text-only or image posts
// • Optional author display data cached on the post (name/photo) for fast lists
// • Likes: likeCount (counter) + likedBy map (per-user flag)
// • Comments: commentCount (counter; actual comments live in subcollection)
// • Tags/categories optional for basic discovery
//
// Firestore shape (superset; all keys optional except authorId/text):
// posts/{postId} {
//   authorId: string,
//   authorName?: string,
//   authorPhotoURL?: string,
//   text: string,
//   imageUrls?: [string],
//   tags?: [string],
//   likeCount?: number,
//   commentCount?: number,
//   likedBy?: { <uid>: true },
//   isEdited?: bool,
//   createdAt?: Timestamp,
//   updatedAt?: Timestamp,
// }
//
// Comments live at: posts/{postId}/comments/{commentId}
//   { authorId, text, createdAt, ... }  (not modeled here)

import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityPost {
  final String id;

  // Author
  final String authorId;
  final String? authorName;
  final String? authorPhotoURL;

  // Content
  final String text;
  final List<String> imageUrls;
  final List<String> tags;

  // Engagement
  final int likeCount;
  final int commentCount;
  final Map<String, bool> likedBy;

  // Meta
  final bool isEdited;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CommunityPost({
    required this.id,
    required this.authorId,
    required this.text,
    this.authorName,
    this.authorPhotoURL,
    this.imageUrls = const [],
    this.tags = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    Map<String, bool>? likedBy,
    this.isEdited = false,
    this.createdAt,
    this.updatedAt,
  }) : likedBy = likedBy ?? const {};

  // ---------------- Helpers ----------------

  bool isLikedBy(String uid) => likedBy[uid] == true;

  CommunityPost copyWith({
    String? id,
    String? authorId,
    String? authorName,
    String? authorPhotoURL,
    String? text,
    List<String>? imageUrls,
    List<String>? tags,
    int? likeCount,
    int? commentCount,
    Map<String, bool>? likedBy,
    bool? isEdited,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommunityPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      text: text ?? this.text,
      authorName: authorName ?? this.authorName,
      authorPhotoURL: authorPhotoURL ?? this.authorPhotoURL,
      imageUrls: imageUrls ?? this.imageUrls,
      tags: tags ?? this.tags,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      likedBy: likedBy ?? this.likedBy,
      isEdited: isEdited ?? this.isEdited,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ---------------- Factories ----------------

  static List<String> _listStr(dynamic v) {
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
    }
    return const <String>[];
  }

  static Map<String, bool> _mapBool(dynamic v) {
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val == true));
    }
    return {};
  }

  static DateTime? _ts(dynamic t) {
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  factory CommunityPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return CommunityPost(
      id: doc.id,
      authorId: (m['authorId'] ?? '').toString(),
      authorName: (m['authorName'] as String?)?.toString(),
      authorPhotoURL: (m['authorPhotoURL'] as String?)?.toString(),
      text: (m['text'] ?? '').toString(),
      imageUrls: _listStr(m['imageUrls']),
      tags: _listStr(m['tags']),
      likeCount: (m['likeCount'] is num) ? (m['likeCount'] as num).toInt() : 0,
      commentCount: (m['commentCount'] is num) ? (m['commentCount'] as num).toInt() : 0,
      likedBy: _mapBool(m['likedBy']),
      isEdited: m['isEdited'] == true,
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  // ---------------- Serialization ----------------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'authorId': authorId,
      if (authorName != null && authorName!.isNotEmpty) 'authorName': authorName,
      if (authorPhotoURL != null && authorPhotoURL!.isNotEmpty) 'authorPhotoURL': authorPhotoURL,
      'text': text,
      if (imageUrls.isNotEmpty) 'imageUrls': imageUrls,
      if (tags.isNotEmpty) 'tags': tags,
      'likeCount': likeCount,
      'commentCount': commentCount,
      if (likedBy.isNotEmpty) 'likedBy': likedBy,
      'isEdited': isEdited,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }
}

// lib/services/verification_service.dart
import 'dart:io';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

enum VerificationMode { online, physical }

String modeToString(VerificationMode m) =>
    m == VerificationMode.online ? 'online' : 'physical';

class FileRef {
  final String path;
  final String url;
  final String name;
  FileRef({required this.path, required this.url, required this.name});

  Map<String, dynamic> toMap() => {'path': path, 'url': url, 'name': name};
  static FileRef fromMap(Map<String, dynamic> m) => FileRef(
    path: m['path'],
    url: m['url'],
    name: m['name'] ?? '',
  );
}

class BasicDocs {
  final String userId;
  final String status; // pending | approved | rejected | needs_more_info
  final FileRef? idCard;
  final FileRef? selfie;
  final FileRef? policeClearance;
  final String? notes;
  final Timestamp updatedAt;

  BasicDocs({
    required this.userId,
    required this.status,
    this.idCard,
    this.selfie,
    this.policeClearance,
    this.notes,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'status': status,
    'idCard': idCard?.toMap(),
    'selfie': selfie?.toMap(),
    'policeClearance': policeClearance?.toMap(),
    'notes': notes,
    'updatedAt': updatedAt,
  };

  static BasicDocs fromSnap(DocumentSnapshot snap) {
    final m = snap.data() as Map<String, dynamic>? ?? {};
    return BasicDocs(
      userId: m['userId'] ?? snap.id,
      status: m['status'] ?? 'pending',
      idCard: m['idCard'] != null
          ? FileRef.fromMap(Map<String, dynamic>.from(m['idCard']))
          : null,
      selfie: m['selfie'] != null
          ? FileRef.fromMap(Map<String, dynamic>.from(m['selfie']))
          : null,
      policeClearance: m['policeClearance'] != null
          ? FileRef.fromMap(Map<String, dynamic>.from(m['policeClearance']))
          : null,
      notes: m['notes'],
      updatedAt: (m['updatedAt'] as Timestamp?) ?? Timestamp.now(),
    );
  }
}

class CategoryProof {
  final String id; // uid_categoryId_mode
  final String userId;
  final String categoryId;
  final String mode; // online | physical
  final String status; // pending | approved | rejected | needs_more_info
  final List<FileRef> files;
  final String? notes;
  final Timestamp updatedAt;

  CategoryProof({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.mode,
    required this.status,
    required this.files,
    this.notes,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'categoryId': categoryId,
    'mode': mode,
    'status': status,
    'files': files.map((f) => f.toMap()).toList(),
    'notes': notes,
    'updatedAt': updatedAt,
  };

  static CategoryProof fromSnap(DocumentSnapshot snap) {
    final m = snap.data() as Map<String, dynamic>? ?? {};
    return CategoryProof(
      id: snap.id,
      userId: m['userId'] ?? '',
      categoryId: m['categoryId'] ?? '',
      mode: m['mode'] ?? 'online',
      status: m['status'] ?? 'pending',
      files: (m['files'] as List<dynamic>? ?? [])
          .map((e) => FileRef.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      notes: m['notes'],
      updatedAt: (m['updatedAt'] as Timestamp?) ?? Timestamp.now(),
    );
  }
}

class VerificationService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get uid {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Not signed in');
    return u.uid;
  }

  /// basic_docs/{uid}
  DocumentReference get _basicDocRef => _fs.collection('basic_docs').doc(uid);

  Future<BasicDocs?> getBasicDocsOnce([String? forUid]) async {
    final ref = _fs.collection('basic_docs').doc(forUid ?? uid);
    final snap = await ref.get();
    if (!snap.exists) return null;
    return BasicDocs.fromSnap(snap);
  }

  Stream<BasicDocs?> watchBasicDocs([String? forUid]) {
    final ref = _fs.collection('basic_docs').doc(forUid ?? uid);
    return ref.snapshots().map((s) => s.exists ? BasicDocs.fromSnap(s) : null);
  }

  Future<void> submitBasicDocs({
    required FileRef idCard,
    required FileRef selfie,
    required FileRef policeClearance,
  }) async {
    await _basicDocRef.set({
      'userId': uid,
      'status': 'pending',
      'idCard': idCard.toMap(),
      'selfie': selfie.toMap(),
      'policeClearance': policeClearance.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// category_proofs/{uid}_{categoryId}_{mode}
  DocumentReference _proofRef(String userId, String categoryId, String mode) =>
      _fs.collection('category_proofs').doc('${userId}_${categoryId}_$mode');

  Stream<List<CategoryProof>> watchMyProofs() {
    return _fs
        .collection('category_proofs')
        .where('userId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((q) => q.docs.map(CategoryProof.fromSnap).toList());
  }

  Future<void> submitCategoryProof({
    required String categoryId,
    required VerificationMode mode,
    required List<FileRef> files,
  }) async {
    final m = modeToString(mode);
    final ref = _proofRef(uid, categoryId, m);
    await ref.set({
      'userId': uid,
      'categoryId': categoryId,
      'mode': m,
      'status': 'pending',
      'files': files.map((f) => f.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------- Storage helpers ----------
  Future<FileRef> uploadToStorage({
    required String localPath,
    required String destPath,
  }) async {
    final storage = FirebaseStorage.instance;
    final file = File(localPath);
    final ref = storage.ref(destPath);
    final task = await ref.putFile(file);
    final url = await task.ref.getDownloadURL();
    final name = ref.name;
    return FileRef(path: destPath, url: url, name: name);
  }
}

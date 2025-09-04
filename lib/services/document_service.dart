// lib/services/document_service.dart
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class Category {
  final String id;
  final String label;
  final String mode; // 'physical' | 'online'
  final String? categoryProofLabel;

  const Category({
    required this.id,
    required this.label,
    required this.mode,
    this.categoryProofLabel,
  });

  factory Category.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    final mode = (m['mode'] ?? 'physical').toString().toLowerCase();
    return Category(
      id: d.id,
      label: (m['label'] ?? d.id).toString(),
      mode: (mode == 'online') ? 'online' : 'physical',
      categoryProofLabel: (m['categoryProofLabel'] as String?),
    );
  }
}

class ProofDoc {
  final String id;        // ${uid}_${categoryId}
  final String uid;
  final String categoryId;
  final String status;    // draft | submitted | pending | verified | rejected | needs_more_info
  final List<String> docUrls;

  const ProofDoc({required this.id, required this.uid, required this.categoryId, required this.status, required this.docUrls});

  factory ProofDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const <String, dynamic>{};
    return ProofDoc.fromMap({'id': d.id, ...m});
  }

  factory ProofDoc.fromMap(Map<String, dynamic> m) {
    final docs = m['documents'];
    final urls = <String>[];
    if (docs is List) {
      for (final x in docs) {
        final u = (x is Map && (x['downloadUrl'] ?? x['url']) != null) ? (x['downloadUrl'] ?? x['url']).toString() : null;
        if (u != null) urls.add(u);
      }
    } else if (docs is Map) {
      for (final v in docs.values) {
        final u = (v is Map && (v['downloadUrl'] ?? v['url']) != null) ? (v['downloadUrl'] ?? v['url']).toString() : null;
        if (u != null) urls.add(u);
      }
    }
    return ProofDoc(
      id: (m['id'] ?? '').toString(),
      uid: (m['uid'] ?? '').toString(),
      categoryId: (m['categoryId'] ?? '').toString(),
      status: (m['status'] ?? 'draft').toString(),
      docUrls: urls,
    );
  }
}

class BootstrapBundle {
  final Map<String, dynamic> user;       // users/{uid} data
  final List<Category> categories;       // from /categories
  final Map<String, ProofDoc> proofs;    // key: 'basic' or categoryId

  const BootstrapBundle({required this.user, required this.categories, required this.proofs});
}

class DocumentService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  Future<Map<String, dynamic>> getUser(String uid) async {
    final d = await _db.collection('users').doc(uid).get();
    return {'id': uid, ...?d.data()};
  }

  Future<List<Category>> getCategories() async {
    try {
      final qs = await _db.collection('categories').get();
      return qs.docs.map((d) => Category.fromDoc(d)).toList(growable: false);
    } catch (_) {
      return const <Category>[];
    }
  }

  Future<Map<String, ProofDoc>> getProofs(String uid) async {
    final out = <String, ProofDoc>{};
    try {
      final b = await _db.collection('category_proofs').doc('${uid}_basic').get();
      if (b.exists) out['basic'] = ProofDoc.fromDoc(b);
      final qs = await _db.collection('category_proofs').where('uid', isEqualTo: uid).get();
      for (final d in qs.docs) {
        final m = ProofDoc.fromDoc(d);
        if (m.categoryId.isNotEmpty && m.categoryId != 'basic') out[m.categoryId] = m;
      }
    } catch (_) {}
    return out;
  }

  Future<BootstrapBundle> bootstrap(String uid) async {
    final user = await getUser(uid);
    final cats = await getCategories();
    final proofs = await getProofs(uid);
    return BootstrapBundle(user: user, categories: cats, proofs: proofs);
  }

  Future<void> updateRegisteredCategories(String uid, List<String> categories) async {
    await _db.collection('users').doc(uid).set({
      'registeredCategories': categories,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pickAndUpload({
    required String uid,
    required String categoryId,
    String logicalName = 'category_proof',
  }) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final bytes = f.bytes;
    final size = f.size;
    if (size > 15 * 1024 * 1024) {
      throw Exception('File too large (max 15 MB).');
    }
    final ext = p.extension(f.name).toLowerCase();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safe = f.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final storagePath = 'proofs/$uid/$categoryId/${logicalName}_$ts\_$safe';

    final meta = SettableMetadata(
      contentType: _guessContentType(ext),
      customMetadata: {
        'uid': uid,
        'categoryId': categoryId,
        'logicalName': logicalName,
        'uploadedAtMs': '$ts',
        'ext': ext,
      },
    );
    UploadTask task;
    if (bytes != null) {
      task = _storage.ref().child(storagePath).putData(bytes, meta);
    } else if (f.path != null) {
      task = _storage.ref().child(storagePath).putFile(File(f.path!), meta);
    } else {
      throw Exception('No file data');
    }
    final snap = await task.whenComplete(() {});
    final url = await snap.ref.getDownloadURL();

    final docRef = _db.collection('category_proofs').doc('${uid}_$categoryId');
    await docRef.set({
      'uid': uid,
      'categoryId': categoryId,
      'updatedAt': FieldValue.serverTimestamp(),
      'documents': FieldValue.arrayUnion([
        {
          'downloadUrl': url,
          'name': f.name,
          'logicalName': logicalName,
          'size': size,
          'ext': ext,
          'uploadedAtMs': ts,
        }
      ])
    }, SetOptions(merge: true));
  }

  Future<void> submitProof({required String uid, required String categoryId}) async {
    final docRef = _db.collection('category_proofs').doc('${uid}_$categoryId');
    await docRef.set({
      'uid': uid,
      'categoryId': categoryId,
      'status': 'submitted',
      'submittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String? _guessContentType(String ext) {
    switch (ext) {
      case '.png': return 'image/png';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      case '.webp': return 'image/webp';
      case '.gif': return 'image/gif';
      case '.pdf': return 'application/pdf';
      default: return null;
    }
  }
}

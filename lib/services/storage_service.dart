
// lib/services/storage_service.dart
//
// Unified storage helper with document-proof helpers.
// NOTE: This file replaces any placeholder implementations.
// It supports both mobile and web by accepting either XFile or Uint8List.
//
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final FirebaseStorage _fs = FirebaseStorage.instance;

  Future<String> _putAndGetUrl(Reference ref, dynamic fileOrBytes, {SettableMetadata? metadata}) async {
    if (fileOrBytes is XFile) {
      await ref.putData(await fileOrBytes.readAsBytes(), metadata);
    } else if (fileOrBytes is Uint8List) {
      await ref.putData(fileOrBytes, metadata);
    } else {
      throw ArgumentError('Unsupported file type. Provide XFile or Uint8List.');
    }
    return ref.getDownloadURL();
  }

  String _ts() => DateTime.now().toUtc().millisecondsSinceEpoch.toString();

  // ---- App-specific helpers ----

  Future<String> uploadUserAvatar(String uid, dynamic fileOrBytes) async {
    final ref = _fs.ref().child('users/$uid/avatar/${_ts()}.jpg');
    return _putAndGetUrl(ref, fileOrBytes, metadata: SettableMetadata(contentType: 'image/jpeg'));
  }

  Future<String> uploadChatImage(String channelId, String uid, dynamic fileOrBytes) async {
    final ref = _fs.ref().child('chat_attachments/$channelId/${_ts()}_$uid.jpg');
    return _putAndGetUrl(ref, fileOrBytes, metadata: SettableMetadata(contentType: 'image/jpeg'));
  }

  /// Uploads a verification document (image/pdf) for a specific category
  /// Path: proofs/{uid}/{categoryId}/{timestamp}_{name}
  Future<String> uploadVerificationDoc({
    required String uid,
    required String categoryId,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    final sanitized = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final path = 'proofs/$uid/$categoryId/${_ts()}_$sanitized';
    final ref = _fs.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType ?? 'application/octet-stream'));
    return ref.getDownloadURL();
  }

  Future<void> deleteByUrl(String url) async {
    try { await _fs.refFromURL(url).delete(); } catch (_) {}
  }
}

// lib/models/dispute_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class DisputeModel {
  final String id;
  final String taskId;
  final String raisedBy;
  final String? posterId;
  final String? helperId;
  final List<String> involved;
  final String reason;
  final List<String> evidenceUrls;
  final String status; // open | resolved | rejected
  final String? resolution; // upheld_poster | upheld_helper | partial | void
  final String? resolutionNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DisputeModel({
    required this.id,
    required this.taskId,
    required this.raisedBy,
    required this.reason,
    required this.status,
    this.posterId,
    this.helperId,
    List<String>? involved,
    List<String>? evidenceUrls,
    this.resolution,
    this.resolutionNotes,
    this.createdAt,
    this.updatedAt,
  })  : involved = involved ?? const [],
        evidenceUrls = evidenceUrls ?? const [];

  factory DisputeModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    DateTime? _ts(dynamic t) {
      if (t is Timestamp) return t.toDate();
      if (t is DateTime) return t;
      return null;
    }
    return DisputeModel(
      id: doc.id,
      taskId: (m['taskId'] ?? '').toString(),
      raisedBy: (m['raisedBy'] ?? '').toString(),
      posterId: (m['posterId'] ?? '').toString().isEmpty ? null : (m['posterId'] ?? '').toString(),
      helperId: (m['helperId'] ?? '').toString().isEmpty ? null : (m['helperId'] ?? '').toString(),
      involved: (m['involved'] is List) ? List<String>.from(m['involved']) : const [],
      reason: (m['reason'] ?? '').toString(),
      evidenceUrls: (m['evidenceUrls'] is List) ? List<String>.from(m['evidenceUrls']) : const [],
      status: (m['status'] ?? 'open').toString(),
      resolution: (m['resolution'] ?? '').toString().isEmpty ? null : (m['resolution'] ?? '').toString(),
      resolutionNotes: (m['resolutionNotes'] ?? '').toString().isEmpty ? null : (m['resolutionNotes'] ?? '').toString(),
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }
}

// lib/models/transaction_model.dart
//
// Transaction model (matches WalletScreen + TopUp + fee flows)
// -----------------------------------------------------------
// Firestore shape (superset; all keys optional except userId/type/amount):
// transactions/{txId} {
//   userId: string,                       // owner of this ledger entry
//   type: 'topup'|'commission'|'post_gate'|'direct_contact_fee'|
//         'milestone'|'refund'|'payout',
//   amount: number,                       // LKR (positive for credit, negative for debit if you prefer)
//   status: 'ok'|'pending'|'failed'|'refunded',
//   note?: string,
//   taskId?: string,                      // if related to a task
//   offerId?: string,                     // optional linkage
//   counterpartyId?: string,              // the other user if relevant
//   direction?: 'credit'|'debit',        // optional explicit direction
//   createdAt?: Timestamp,
//   updatedAt?: Timestamp
// }

import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionModel {
  final String id;

  final String userId;
  final String type;             // topup | commission | post_gate | direct_contact_fee | milestone | refund | payout
  final int amount;              // LKR
  final String status;           // ok | pending | failed | refunded

  final String? note;
  final String? taskId;
  final String? offerId;
  final String? counterpartyId;
  final String? direction;       // credit | debit (optional, UI can derive from sign of amount)

  final DateTime? createdAt;
  final DateTime? updatedAt;

  TransactionModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.status,
    this.note,
    this.taskId,
    this.offerId,
    this.counterpartyId,
    this.direction,
    this.createdAt,
    this.updatedAt,
  });

  // ---------------- Safe parsers ----------------

  static int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _ts(dynamic t) {
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return null;
  }

  // ---------------- Factories ----------------

  factory TransactionModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    return TransactionModel(
      id: doc.id,
      userId: (m['userId'] ?? '').toString(),
      type: (m['type'] ?? 'topup').toString(),
      amount: _asInt(m['amount']),
      status: (m['status'] ?? 'ok').toString(),
      note: (m['note'] as String?)?.toString(),
      taskId: (m['taskId'] as String?)?.toString(),
      offerId: (m['offerId'] as String?)?.toString(),
      counterpartyId: (m['counterpartyId'] as String?)?.toString(),
      direction: (m['direction'] as String?)?.toString(),
      createdAt: _ts(m['createdAt']),
      updatedAt: _ts(m['updatedAt']),
    );
  }

  factory TransactionModel.fromMap(String id, Map<String, dynamic> m) {
    final fake = _FakeDoc(id, m);
    return TransactionModel.fromDoc(fake);
  }

  // ---------------- Serialization ----------------

  Map<String, dynamic> toMap({bool includeTimestamps = true}) {
    final out = <String, dynamic>{
      'userId': userId,
      'type': type,
      'amount': amount,
      'status': status,
      if (note != null && note!.isNotEmpty) 'note': note,
      if (taskId != null && taskId!.isNotEmpty) 'taskId': taskId,
      if (offerId != null && offerId!.isNotEmpty) 'offerId': offerId,
      if (counterpartyId != null && counterpartyId!.isNotEmpty) 'counterpartyId': counterpartyId,
      if (direction != null && direction!.isNotEmpty) 'direction': direction,
    };
    if (includeTimestamps) {
      out['updatedAt'] = FieldValue.serverTimestamp();
      if (createdAt == null) out['createdAt'] = FieldValue.serverTimestamp();
    }
    return out;
  }

  // ---------------- Helpers ----------------

  bool get isCredit => (direction == 'credit') || (direction == null && amount >= 0);
  bool get isDebit  => (direction == 'debit')  || (direction == null && amount < 0);
  bool get isOk => status == 'ok';
  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  bool get isRefunded => status == 'refunded';

  TransactionModel copyWith({
    String? id,
    String? userId,
    String? type,
    int? amount,
    String? status,
    String? note,
    String? taskId,
    String? offerId,
    String? counterpartyId,
    String? direction,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      note: note ?? this.note,
      taskId: taskId ?? this.taskId,
      offerId: offerId ?? this.offerId,
      counterpartyId: counterpartyId ?? this.counterpartyId,
      direction: direction ?? this.direction,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// Tiny adapter so we can reuse fromDoc for raw map inputs.
class _FakeDoc implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDoc(this._id, this._data);
  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;
  @override
  Map<String, dynamic>? data() => _data;
  @override
  bool get exists => true;

  // Unused members to satisfy the interface
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
  @override
  DocumentReference<Map<String, dynamic>> get reference => throw UnimplementedError();
  @override
  dynamic /* Map<String, dynamic> | T */ get(DataSource? source) => _data;
  @override
  dynamic operator [](Object field) => _data[field];
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

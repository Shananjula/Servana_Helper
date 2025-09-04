// lib/services/functions_service.dart
// Wrapper for callable Cloud Functions: approveOffer & createTopUp

import 'package:cloud_functions/cloud_functions.dart';

class FunctionsService {
  FunctionsService._();
  static final FunctionsService instance = FunctionsService._();
  factory FunctionsService() => instance;

  final FirebaseFunctions _func = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> approveOffer({
    required String taskId,
    required String offerId,
  }) async {
    final callable = _func.httpsCallable('approveOffer');
    final res = await callable.call(<String, dynamic>{ 'taskId': taskId, 'offerId': offerId });
    final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    return data;
  }

  Future<Map<String, dynamic>> createTopUp({required int amount}) async {
    final callable = _func.httpsCallable('createTopUp');
    final res = await callable.call(<String, dynamic>{ 'amount': amount });
    final data = (res.data is Map) ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    return data;
  }
}

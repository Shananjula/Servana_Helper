
// lib/utils/chat_id.dart
String _sanitize(String s) {
  final safe = s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
  return safe.isEmpty ? '_' : safe;
}
String _sortedPair(String a, String b) {
  final aa = _sanitize(a);
  final bb = _sanitize(b);
  return (aa.compareTo(bb) <= 0) ? '${aa}_${bb}' : '${bb}_${aa}';
}
class ChatId {
  static String forTask({required String uidA, required String uidB, required String taskId}) {
    return '${_sanitize(taskId)}_${_sortedPair(uidA, uidB)}';
  }
  static String forDirect({required String uidA, required String uidB}) {
    return _sortedPair(uidA, uidB);
  }
}
String chatIdForTaskPair({required String taskId, required String posterId, required String helperId}) {
  return ChatId.forTask(uidA: posterId, uidB: helperId, taskId: taskId);
}

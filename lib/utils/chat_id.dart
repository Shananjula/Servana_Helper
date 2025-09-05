// lib/utils/chat_id.dart
// Canonical chat channel IDs for consistency across Poster & Helper.
// - Task-bound chats: "<minUid>_<maxUid>_<taskId>"
// - Direct (non-task) chats: "<minUid>_<maxUid>"

class ChatId {
  static String _sort2(String a, String b) {
    // Use braces to avoid '$a_$b' being parsed as 'a_' + '$b'
    return (a.compareTo(b) <= 0) ? '${a}_${b}' : '${b}_${a}';
  }

  static String forTask({
    required String uidA,
    required String uidB,
    required String taskId,
  }) {
    final base = _sort2(uidA, uidB);
    return '${base}_$taskId';
  }

  static String forDirect({
    required String uidA,
    required String uidB,
  }) {
    return _sort2(uidA, uidB);
  }
}

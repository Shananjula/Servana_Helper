// lib/services/chat_id.dart
String chatIdFor({required String posterId, required String helperId, required String taskId}) {
  return 'task_${taskId}__poster_${posterId}__helper_${helperId}';
}

import 'package:uuid/uuid.dart';

/// Saved with the account document. Actions are proposals until applied.
class ChatMessage {
  final String id, role, content;
  final List<Map<String, dynamic>> actions;
  final List<int> applied;
  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    this.actions = const [],
    this.applied = const [],
  }) : id = id ?? const Uuid().v4();

  ChatMessage markApplied(int index) => ChatMessage(
    id: id,
    role: role,
    content: content,
    actions: actions,
    applied: {...applied, index}.toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'actions': actions,
    'applied': applied,
  };
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    actions: (json['actions'] as List? ?? [])
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList(),
    applied: (json['applied'] as List? ?? []).cast<int>(),
  );
  Map<String, dynamic> toHistory() => {
    'role': role,
    'content': role == 'assistant'
        ? {'message': content, 'actions': actions, 'applied': applied}
        : content,
  };
}

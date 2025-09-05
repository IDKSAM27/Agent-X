import 'package:equatable/equatable.dart';

enum MessageType { user, assistant, system }
enum MessageStatus { sending, sent, delivered, failed }

class ChatMessage extends Equatable {
  final String id;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final MessageStatus status;
  final bool isTyping;
  final Map<String, dynamic>? metadata; // Add metadata field

  const ChatMessage({
    required this.id,
    required this.content,
    required this.type,
    required this.timestamp,
    this.status = MessageStatus.sent,
    this.isTyping = false,
    this.metadata, // Add metadata parameter
  });

  ChatMessage copyWith({
    String? id,
    String? content,
    MessageType? type,
    DateTime? timestamp,
    MessageStatus? status,
    bool? isTyping,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isTyping: isTyping ?? this.isTyping,
      metadata: metadata ?? this.metadata, // Include in copyWith
    );
  }

  @override
  List<Object?> get props => [id, content, type, timestamp, status, isTyping, metadata];
}

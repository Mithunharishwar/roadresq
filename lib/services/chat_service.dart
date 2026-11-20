// FILE: lib/services/chat_service.dart
/// ChatService — In-App Chat between User and Crew.
///
/// Implements: chatWithCrew(jobId, message)
/// Stores messages under `chats/{jobId}/messages`.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
  });

  factory ChatMessage.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      message: data['message'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class ChatService {
  ChatService._internal();
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// chatWithCrew(jobId, message) — send a message in the job chat thread.
  Future<bool> chatWithCrew({
    required String jobId,
    required String senderId,
    required String senderName,
    required String message,
  }) async {
    try {
      await _firestore
          .collection('chats')
          .doc(jobId)
          .collection('messages')
          .add({
        'senderId': senderId,
        'senderName': senderName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('ChatService.chatWithCrew error: $e');
      return false;
    }
  }

  /// Stream messages for a job thread.
  Stream<List<ChatMessage>> streamMessages(String jobId) {
    return _firestore
        .collection('chats')
        .doc(jobId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromDocument(d)).toList());
  }
}

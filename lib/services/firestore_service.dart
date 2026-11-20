// IMPORTANT: Set Firestore Rules to allow read/write for testing
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// FirestoreService — Centralized Firestore CRUD operations
/// Provides typed read/write/listen operations for all collections.
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Singleton ───
  FirestoreService._internal();
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;

  // ─── Generic CRUD ───

  /// Create a document with auto-generated ID
  Future<String> createDocument({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    try {
      final docRef = await _firestore.collection(collection).add(data);
      return docRef.id;
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService.createDocument FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      rethrow;
    } catch (e) {
      debugPrint('FirestoreService.createDocument error: $e');
      rethrow;
    }
  }

  /// Create a document with specific ID
  Future<void> setDocument({
    required String collection,
    required String documentId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    try {
      await _firestore
          .collection(collection)
          .doc(documentId)
          .set(data, SetOptions(merge: merge));
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService.setDocument FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      rethrow;
    } catch (e) {
      debugPrint('FirestoreService.setDocument error: $e');
      rethrow;
    }
  }

  /// Read a document
  Future<DocumentSnapshot?> getDocument({
    required String collection,
    required String documentId,
  }) async {
    try {
      return await _firestore.collection(collection).doc(documentId).get();
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService.getDocument FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return null;
    } catch (e) {
      debugPrint('FirestoreService.getDocument error: $e');
      return null;
    }
  }

  /// Update a document
  Future<void> updateDocument({
    required String collection,
    required String documentId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _firestore.collection(collection).doc(documentId).update(updates);
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService.updateDocument FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      rethrow;
    } catch (e) {
      debugPrint('FirestoreService.updateDocument error: $e');
      rethrow;
    }
  }

  /// Delete a document
  Future<void> deleteDocument({
    required String collection,
    required String documentId,
  }) async {
    try {
      await _firestore.collection(collection).doc(documentId).delete();
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService.deleteDocument FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      rethrow;
    } catch (e) {
      debugPrint('FirestoreService.deleteDocument error: $e');
      rethrow;
    }
  }

  // ─── Queries ───

  /// Get all documents in a collection (with optional filters)
  Future<List<QueryDocumentSnapshot>> queryDocuments({
    required String collection,
    String? orderBy,
    bool descending = true,
    int? limit,
    List<WhereClause>? whereClauses,
  }) async {
    try {
      Query query = _firestore.collection(collection);

      if (whereClauses != null) {
        for (final clause in whereClauses) {
          query = query.where(
            clause.field,
            isEqualTo: clause.isEqualTo,
            isNotEqualTo: clause.isNotEqualTo,
            isLessThan: clause.isLessThan,
            isLessThanOrEqualTo: clause.isLessThanOrEqualTo,
            isGreaterThan: clause.isGreaterThan,
            isGreaterThanOrEqualTo: clause.isGreaterThanOrEqualTo,
            arrayContains: clause.arrayContains,
            arrayContainsAny: clause.arrayContainsAny,
            whereIn: clause.whereIn,
            whereNotIn: clause.whereNotIn,
          );
        }
      }

      if (orderBy != null) {
        query = query.orderBy(orderBy, descending: descending);
      }

      if (limit != null) {
        query = query.limit(limit);
      }

      final snapshot = await query.get();
      return snapshot.docs;
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService.queryDocuments FirebaseException: ${e.code} - ${e.message}');
      if (e.code == 'permission-denied') {
        debugPrint('PERMISSION_DENIED: Check Firestore Rules');
      }
      return [];
    } catch (e) {
      debugPrint('FirestoreService.queryDocuments error: $e');
      return [];
    }
  }

  // ─── Real-time Streams ───

  /// Stream a single document
  Stream<DocumentSnapshot> streamDocument({
    required String collection,
    required String documentId,
  }) {
    return _firestore.collection(collection).doc(documentId).snapshots();
  }

  /// Stream a collection query
  Stream<QuerySnapshot> streamCollection({
    required String collection,
    String? orderBy,
    bool descending = true,
    int? limit,
    List<WhereClause>? whereClauses,
  }) {
    Query query = _firestore.collection(collection);

    if (whereClauses != null) {
      for (final clause in whereClauses) {
        query = query.where(
          clause.field,
          isEqualTo: clause.isEqualTo,
          isNotEqualTo: clause.isNotEqualTo,
          isLessThan: clause.isLessThan,
          isLessThanOrEqualTo: clause.isLessThanOrEqualTo,
          isGreaterThan: clause.isGreaterThan,
          isGreaterThanOrEqualTo: clause.isGreaterThanOrEqualTo,
          arrayContains: clause.arrayContains,
          arrayContainsAny: clause.arrayContainsAny,
          whereIn: clause.whereIn,
          whereNotIn: clause.whereNotIn,
        );
      }
    }

    if (orderBy != null) {
      query = query.orderBy(orderBy, descending: descending);
    }

    if (limit != null) {
      query = query.limit(limit);
    }

    return query.snapshots();
  }
}

/// Helper class for Firestore where clauses
class WhereClause {
  final String field;
  final dynamic isEqualTo;
  final dynamic isNotEqualTo;
  final dynamic isLessThan;
  final dynamic isLessThanOrEqualTo;
  final dynamic isGreaterThan;
  final dynamic isGreaterThanOrEqualTo;
  final dynamic arrayContains;
  final List<dynamic>? arrayContainsAny;
  final List<dynamic>? whereIn;
  final List<dynamic>? whereNotIn;

  WhereClause({
    required this.field,
    this.isEqualTo,
    this.isNotEqualTo,
    this.isLessThan,
    this.isLessThanOrEqualTo,
    this.isGreaterThan,
    this.isGreaterThanOrEqualTo,
    this.arrayContains,
    this.arrayContainsAny,
    this.whereIn,
    this.whereNotIn,
  });
}

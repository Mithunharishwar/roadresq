/// RoadResQ Token Provider
/// Core Patent: Digital Vehicle Token System
///
/// Manages the full token lifecycle:
/// generated → handed_to_garage → repair_started → ready_for_pickup → closed
///
/// All 3 parties (User, Crew, Garage) can track token status in real-time.
/// QR code generation and validation for secure vehicle handover.
library;

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../core/constants/app_constants.dart';
import '../models/token_model.dart';
import '../services/firestore_service.dart';

/// Duration a token remains valid before it expires (Feature 2).
const Duration tokenTtl = Duration(minutes: 30);

/// ─── State ───
class TokenState {
  final bool isLoading;
  final String? errorMessage;
  final TokenModel? currentToken;
  final List<TokenModel> tokens;
  final String? scannedTokenCode;
  final String? validatedTokenId;
  final bool isValidating;

  const TokenState({
    this.isLoading = false,
    this.errorMessage,
    this.currentToken,
    this.tokens = const [],
    this.scannedTokenCode,
    this.validatedTokenId,
    this.isValidating = false,
  });

  TokenState copyWith({
    bool? isLoading,
    String? errorMessage,
    TokenModel? currentToken,
    List<TokenModel>? tokens,
    String? scannedTokenCode,
    String? validatedTokenId,
    bool? isValidating,
  }) {
    return TokenState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      currentToken: currentToken ?? this.currentToken,
      tokens: tokens ?? this.tokens,
      scannedTokenCode: scannedTokenCode ?? this.scannedTokenCode,
      validatedTokenId: validatedTokenId ?? this.validatedTokenId,
      isValidating: isValidating ?? this.isValidating,
    );
  }
}

/// ─── Notifier ───
class TokenNotifier extends StateNotifier<TokenState> {
  final FirestoreService _firestore;
  // Random.secure() uses a CSPRNG. A vehicle token authorises a physical
  // handover, so a predictable PRNG (plain Random()) is not acceptable.
  final Random _random = Random.secure();

  TokenNotifier(this._firestore) : super(const TokenState());

  /// ─── PATENT: Generate 6-digit alphanumeric token ───
  /// Uses a character set that avoids confusion (no 0/O, 1/I/L).
  String _generateTokenCode() {
    const chars = AppConstants.tokenChars;
    final code = List.generate(AppConstants.tokenLength, (_) {
      return chars[_random.nextInt(chars.length)];
    }).join();
    return code;
  }

  /// ─── Generate a new digital vehicle token ───
  /// Links: UserID + CrewID + GarageID + VehicleNo + Timestamp
  Future<TokenModel?> generateToken({
    required String userId,
    required String crewId,
    required String garageId,
    required String vehicleNumber,
    String vehicleType = '',
    String? garageName,
    String? garagePhone,
    String issuedFor = 'garage_pickup',
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final tokenCode = _generateTokenCode();
      final now = DateTime.now();
      final expiry = now.add(tokenTtl);

      final tokenData = {
        'tokenCode': tokenCode,
        'qrUrl': '', // QR would be generated client-side via qr_flutter
        'userId': userId,
        'crewId': crewId,
        'garageId': garageId,
        'vehicleNumber': vehicleNumber,
        'vehicleType': vehicleType,
        'status': 'generated',
        'garageName': garageName ?? '',
        'garagePhone': garagePhone ?? '',
        // ── Security (Feature 2) ──
        'expiresAt': Timestamp.fromDate(expiry),
        'issuedFor': issuedFor,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      };

      final tokenId = await _firestore.createDocument(
        collection: AppConstants.collectionTokens,
        data: tokenData,
      );

      final doc = await _firestore.getDocument(
        collection: AppConstants.collectionTokens,
        documentId: tokenId,
      );

      if (doc != null && doc.exists) {
        final token = TokenModel.fromFirestore(doc);
        state = state.copyWith(
          currentToken: token,
          isLoading: false,
        );
        return token;
      }

      state = state.copyWith(isLoading: false);
      return null;
    } catch (e) {
      debugPrint('TokenNotifier.generateToken error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to generate token: ${e.toString()}',
      );
      return null;
    }
  }

  /// ─── PATENT: Update token status through lifecycle ───
  /// Flow: generated → handed_to_garage → repair_started → ready_for_pickup → closed
  Future<void> updateTokenStatus({
    required String tokenId,
    required String status,
    String? notes,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': status,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      // Set the appropriate timestamp based on status
      switch (status) {
        case 'handed_to_garage':
          updates['handedOverAt'] = Timestamp.fromDate(DateTime.now());
          break;
        case 'repair_started':
          updates['repairStartedAt'] = Timestamp.fromDate(DateTime.now());
          break;
        case 'ready_for_pickup':
          updates['readyForPickupAt'] = Timestamp.fromDate(DateTime.now());
          break;
        case 'closed':
          updates['closedAt'] = Timestamp.fromDate(DateTime.now());
          break;
      }

      if (notes != null) {
        updates['notes'] = notes;
      }

      await _firestore.updateDocument(
        collection: AppConstants.collectionTokens,
        documentId: tokenId,
        updates: updates,
      );

      // Refresh local state
      if (state.currentToken?.id == tokenId) {
        final updated = state.currentToken!.copyWith(
          status: status,
          notes: notes,
          handedOverAt: status == 'handed_to_garage' ? DateTime.now() : null,
          repairStartedAt: status == 'repair_started' ? DateTime.now() : null,
          readyForPickupAt:
              status == 'ready_for_pickup' ? DateTime.now() : null,
          closedAt: status == 'closed' ? DateTime.now() : null,
        );
        state = state.copyWith(currentToken: updated);
      }
    } catch (e) {
      debugPrint('TokenNotifier.updateTokenStatus error: $e');
      state = state.copyWith(
        errorMessage: 'Failed to update token: ${e.toString()}',
      );
    }
  }

  /// ─── Validate a scanned token code ───
  /// Used by QR scanner to verify token authenticity.
  ///
  /// Security (Feature 2): delegates to the `verifyToken` Cloud Function,
  /// which atomically checks expiry + one-time use and marks the token as
  /// consumed in a Firestore transaction. This prevents screenshot/QR reuse.
  Future<bool> validateTokenCode(String tokenCode) async {
    state = state.copyWith(isValidating: true, scannedTokenCode: tokenCode);

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyToken')({'tokenCode': tokenCode});

      final data = result.data as Map<String, dynamic>;
      final success = data['success'] == true;
      final tokenData = data['token'] as Map<String, dynamic>?;

      if (success && tokenData != null) {
        final tokenId = data['tokenId'] as String? ?? '';
        final token = TokenModel(
          id: tokenId,
          tokenCode: tokenData['tokenCode'] ?? tokenCode,
          qrUrl: tokenData['qrUrl'] ?? '',
          userId: tokenData['userId'] ?? '',
          crewId: tokenData['crewId'] ?? '',
          garageId: tokenData['garageId'] ?? '',
          vehicleNumber: tokenData['vehicleNumber'] ?? '',
          vehicleType: tokenData['vehicleType'] ?? '',
          status: tokenData['status'] ?? 'generated',
          garageName: tokenData['garageName'],
          garagePhone: tokenData['garagePhone'],
          garageAddress: tokenData['garageAddress'],
          notes: tokenData['notes'],
          expiresAt: _parseTimestamp(tokenData['expiresAt']),
          consumedAt: _parseTimestamp(tokenData['consumedAt']),
          issuedFor: tokenData['issuedFor'],
        );

        state = state.copyWith(
          validatedTokenId: tokenId,
          currentToken: token,
          isValidating: false,
        );
        return true;
      }

      state = state.copyWith(
        isValidating: false,
        errorMessage: data['message'] ?? 'Invalid token code',
      );
      return false;
    } catch (e) {
      debugPrint('TokenNotifier.validateTokenCode error: $e');
      state = state.copyWith(
        isValidating: false,
        errorMessage: 'Failed to validate token: ${e.toString()}',
      );
      return false;
    }
  }

  /// Parses a timestamp from the Cloud Function response payload.
  /// The value may be a Firestore Timestamp, a DateTime, or a numeric
  /// (milliseconds since epoch) depending on how the function serializes it.
  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) {
      // Firestore-Timestamp-like _seconds/_nanoseconds map, or epoch millis.
      if (value.toInt() > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
    }
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      final millis =
          value['_milliseconds'] ?? value['milliseconds'] ?? (seconds * 1000);
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  /// ─── Fetch token by ID ───
  Future<void> fetchToken(String tokenId) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final doc = await _firestore.getDocument(
        collection: AppConstants.collectionTokens,
        documentId: tokenId,
      );

      if (doc != null && doc.exists) {
        final token = TokenModel.fromFirestore(doc);
        state = state.copyWith(currentToken: token, isLoading: false);
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Token not found',
        );
      }
    } catch (e) {
      debugPrint('TokenNotifier.fetchToken error: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to fetch token: ${e.toString()}',
      );
    }
  }

  /// ─── Fetch all tokens for a user ───
  Future<void> fetchUserTokens(String userId) async {
    try {
      final docs = await _firestore.queryDocuments(
        collection: AppConstants.collectionTokens,
        whereClauses: [
          WhereClause(field: 'userId', isEqualTo: userId),
        ],
        orderBy: 'createdAt',
        descending: true,
        limit: 20,
      );

      final tokens = docs.map((doc) => TokenModel.fromFirestore(doc)).toList();
      state = state.copyWith(tokens: tokens);
    } catch (e) {
      debugPrint('TokenNotifier.fetchUserTokens error: $e');
    }
  }

  /// ─── Fetch all tokens for a garage ───
  Future<void> fetchGarageTokens(String garageId) async {
    try {
      final docs = await _firestore.queryDocuments(
        collection: AppConstants.collectionTokens,
        whereClauses: [
          WhereClause(field: 'garageId', isEqualTo: garageId),
        ],
        orderBy: 'createdAt',
        descending: true,
        limit: 50,
      );

      final tokens = docs.map((doc) => TokenModel.fromFirestore(doc)).toList();
      state = state.copyWith(tokens: tokens);
    } catch (e) {
      debugPrint('TokenNotifier.fetchGarageTokens error: $e');
    }
  }

  /// ─── Close a token (final status) ───
  Future<void> closeToken(String tokenId) async {
    await updateTokenStatus(tokenId: tokenId, status: 'closed');
  }

  /// Reset state
  void reset() {
    state = const TokenState();
  }
}

/// ─── Provider ───
final tokenProvider = StateNotifierProvider<TokenNotifier, TokenState>(
  (ref) {
    return TokenNotifier(FirestoreService());
  },
);

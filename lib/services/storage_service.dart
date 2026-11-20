import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../core/constants/app_constants.dart';

/// StorageService — Firebase Cloud Storage operations
/// Handles image uploads for KYC, vehicle photos, issue photos, and profile pictures.
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ─── Singleton ───
  StorageService._internal();
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;

  /// Upload a file from a local path
  Future<String?> uploadFile({
    required String filePath,
    required String storagePath,
    String? fileName,
  }) async {
    try {
      final file = File(filePath);
      final ref = _storage.ref().child(
            '$storagePath/${fileName ?? DateTime.now().millisecondsSinceEpoch.toString()}',
          );
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('StorageService.uploadFile error: $e');
      return null;
    }
  }

  /// Upload bytes data (e.g., captured image from camera)
  Future<String?> uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    String? fileName,
  }) async {
    try {
      final ref = _storage.ref().child(
            '$storagePath/${fileName ?? DateTime.now().millisecondsSinceEpoch.toString()}',
          );
      final uploadTask = await ref.putData(bytes);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('StorageService.uploadBytes error: $e');
      return null;
    }
  }

  /// Delete a file
  Future<bool> deleteFile(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      return true;
    } catch (e) {
      debugPrint('StorageService.deleteFile error: $e');
      return false;
    }
  }

  /// Upload KYC document
  Future<String?> uploadKycDocument({
    required String filePath,
    required String userId,
  }) async {
    return uploadFile(
      filePath: filePath,
      storagePath: '${AppConstants.storageKycDocs}/$userId',
    );
  }

  /// Upload vehicle photo
  Future<String?> uploadVehiclePhoto({
    required String filePath,
    required String userId,
  }) async {
    return uploadFile(
      filePath: filePath,
      storagePath: '${AppConstants.storageVehiclePhotos}/$userId',
    );
  }

  /// Upload issue photo
  Future<String?> uploadIssuePhoto({
    required String filePath,
    required String requestId,
  }) async {
    return uploadFile(
      filePath: filePath,
      storagePath: '${AppConstants.storageIssuePhotos}/$requestId',
    );
  }

  /// Upload profile picture
  Future<String?> uploadProfilePicture({
    required String filePath,
    required String userId,
  }) async {
    return uploadFile(
      filePath: filePath,
      storagePath: '${AppConstants.storageProfilePics}/$userId',
    );
  }
}

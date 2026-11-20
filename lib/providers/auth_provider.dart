import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

/// AuthProvider — Riverpod state management for authentication
/// Manages auth state, user profile, and login/signup operations.

// State class
class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final User? firebaseUser;
  final UserModel? userProfile;
  final bool isAuthenticated;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.firebaseUser,
    this.userProfile,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    User? firebaseUser,
    UserModel? userProfile,
    bool? isAuthenticated,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      firebaseUser: firebaseUser ?? this.firebaseUser,
      userProfile: userProfile ?? this.userProfile,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

// Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(const AuthState()) {
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  void _onAuthStateChanged(User? user) {
    if (user != null) {
      state = state.copyWith(
        firebaseUser: user,
        isAuthenticated: true,
        errorMessage: null,
      );
      _loadUserProfile(user.uid);
    } else {
      state = const AuthState();
    }
  }

  Future<void> _loadUserProfile(String userId) async {
    final profile = await _authService.getUserProfile(userId);
    if (profile != null) {
      state = state.copyWith(userProfile: profile);
    }
  }

  Future<void> loginWithEmail({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _authService.loginWithEmail(email: email, password: password);
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final credential = await _authService.registerWithEmail(
        email: email,
        password: password,
      );
      // Create user profile
      final user = UserModel(
        id: credential.user!.uid,
        name: name,
        phone: phone,
        email: email,
        role: 'user',
      );
      await _authService.updateUserProfile(user);
      state = state.copyWith(
        isLoading: false,
        userProfile: user,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    state = const AuthState();
  }

  Future<void> updateProfile(UserModel user) async {
    await _authService.updateUserProfile(user);
    state = state.copyWith(userProfile: user);
  }
}

// Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(AuthService());
});
